# Google Workspace CLI auth that survives past 16 hours

How to drive many Google accounts from one machine with [`googleworkspace-cli`](https://github.com/googleworkspace/google-workspace-cli)
(`gws`), and how to stop tokens dying overnight with `invalid_rapt`.

This is the part of an agent workspace that nobody writes down, so it gets
re-learned the expensive way every time. Everything here came out of running it
across a dozen accounts (personal Gmail, several Workspace domains, one employer
domain) for about a year.

## The problem

`gws` authenticates one Google account against one config dir. If you want an
agent to read your mail, write to your Drive, and check Search Console across
several identities, you need a wrapper.

That part is easy. The part that is not easy is that your tokens keep dying:

```
invalid_grant: reauth related error (invalid_rapt)
```

RAPT is Google's Re-Authentication Proof Token. The error means Google decided the
session behind this refresh token needs a human, and a CLI has no way to provide
one. In practice tokens die roughly every 16 hours, which is Google Cloud session
control's default reauthentication policy.

## Layout

```
.gws-accounts.json               alias -> email, project, credential paths (gitignored)
.credentials/<alias>.json        exported refresh token per account (gitignored)
~/.config/gws/accounts/<alias>/  per-account isolated gws config + keyring
scripts/gws/                     the wrapper and its tooling
terraform/gws-project/           one GCP project per account
```

Each account owns **its own GCP project**, which owns the OAuth client that issues
its tokens. That is not cosmetic. Sharing one project across accounts puts every
non-owner in "test user" mode on an unpublished consent screen, and Google
re-challenges those aggressively, sometimes within hours.

## Setup

```bash
brew install --cask google-cloud-sdk
brew install jq terraform
./scripts/gws/gws-install-binary.sh

cp .gws-accounts.example.json .gws-accounts.json   # then edit it
mkdir -p .credentials

gcloud auth application-default login              # as the account that owns the org
```

Then per account:

1. **Create a GCP project** owned by that account's own identity or org.
   `terraform/gws-project/` does this.
2. **Set the OAuth consent screen**, per the table below.
3. **Create a Desktop OAuth client** (not "Web application", the CLI uses the
   installed-app loopback flow). Download the JSON to
   `.credentials/client_secret_<alias>.json`.
4. **Register and log in.** Add the account to `.gws-accounts.json`, then
   `./scripts/gws/gws-auth-setup.sh --account <alias>`.
5. **Handle reauth.** See below. This is the step everyone skips and then pays for.
6. **Get it monitored.** `gws-healthcheck-alert.sh` on a 6h cron. An account that
   is not in a swept registry is silently unmonitored, and you find out mid-task.

## Consent screen: Internal vs External

| Account type | Audience | Extra step | Project requirement |
|---|---|---|---|
| Workspace domain | **Internal** | none, no publishing | project must live **inside** that Workspace's Cloud Identity org |
| Consumer Gmail | **External** | must click **Publish App** | org-less project is fine |

Two traps.

- **A project's org is fixed at creation and cannot be changed afterwards.** Create
  it org-less and Internal is permanently unavailable to that project. You have to
  delete and recreate.
- **External and unpublished** puts everyone in test-user mode. This is the single
  most common cause of "my token died again after two hours".

## Fixing invalid_rapt

Which fix applies depends on whether you administer the domain. Diagnose before
acting.

```
invalid_rapt
├─ Consumer Gmail?
│    └─ Consent screen is External and unpublished. Publish it.
│
└─ Workspace domain?
     └─ Do you administer that domain?
        ├─ YES -> Google Cloud session control's reauth policy is on. Turn it off,
        │         ideally scoped to a group. See below.
        │
        └─ NO  -> You cannot change the policy, so do not enter it.
                  Authenticate without a Google Cloud scope. See below.
```

### If you administer the domain

Manual, to unblock right now. admin.google.com > Security > Access and data
control > Google Cloud session control > Reauthentication policy > **Never require
reauthentication**. Org-wide and blunt.

In code, and much better scoped. A Cloud Identity group containing only the
accounts that need CLI access, plus a
`google_access_context_manager_gcp_user_access_binding` exempting that group. The
org-wide policy stays intact.

```hcl
session_settings {
  session_length         = "86400s"
  session_length_enabled = false   # false means infinite session, never reauth
  session_reauth_method  = "LOGIN"
}
```

Four counterintuitive things, each of which cost real time to learn.

1. **`session_length_enabled = false` is the goal.** It means infinite session. The
   `session_length` value is then ignored and only exists to dodge a provider
   validation error.
2. **`session_length = "0s"` with `enabled = true` is a lockout.** Google reads
   zero-length as "disable the session", meaning constant reauth, meaning every
   member of the bound group loses GCP access. This is not hypothetical, it has
   locked real users out.
3. **Durations must be seconds-form.** `"24h"` fails with "Illegal duration format;
   duration must end with 's'".
4. **Omitting `session_reauth_method` causes a permanent plan diff**, because the
   server defaults it to `LOGIN`.

The role you need is `roles/accesscontextmanager.gcpAccessAdmin`, which carries
`accesscontextmanager.gcpUserAccessBindings.*`. It is **not** `policyAdmin`, which
only manages access policies and levels. Being a Workspace super-admin does not
grant it. Expect a 403 loop if you confuse the two.

**Escape hatch.** admin.google.com runs its own separate session that is *not*
gated by Cloud session control, so the Admin console still works when GCP does
not. Remove the affected user from the bound group there and access returns
immediately. Which is why the break-glass super-admin must never be a member of
the bound group.

### If you do NOT administer the domain

This is the employer case, and it is why this doc exists. You cannot flip the
policy and you cannot create the binding. Every fix above is unavailable.

The lever you do have is **scope selection**. Google Cloud session control applies
its reauth clock to tokens carrying **Google Cloud OAuth scopes**. Nothing in
Workspace needs one:

| What you use | Scopes | Cloud scope? |
|---|---|---|
| Gmail read/send/settings | `gmail.modify`, `gmail.settings.*` | No |
| Drive, Docs, Sheets, Slides | `drive`, `documents`, `spreadsheets`, `presentations` | No |
| Calendar, Contacts, Tasks | `calendar`, `contacts`, `tasks` | No |
| Search Console | `webmasters`, `siteverification` | No |

`gws`'s own help is the tell. `gws auth login --full` is documented as "Request all
scopes **incl. pubsub + cloud-platform**", so Cloud Platform is the opt-in extra,
not the baseline. It is very easy to have hardcoded it into your login script years
ago and never notice.

Authenticate without it and the token never enters the session that the reauth
clock governs. No org policy touched, nothing to ask anyone for.

```json
"work": { "scopes": "workspace-no-cloud", ... }
```

```bash
./scripts/gws/gws-auth-setup.sh --account work
./scripts/gws/gws-check-scopes.sh work     # verify what Google actually GRANTED
```

**Verify, do not assume.** What you requested and what Google granted can differ,
because re-authenticating against a stale cached consent quietly preserves the old
scope set. Only the minted token is evidence, which is what `gws-check-scopes.sh`
reads. If it still reports a Cloud scope, revoke the app's access in your Google
account settings and authenticate again.

**Honest caveat.** That Google keys the reauth clock to Cloud scopes is documented
and the scope is provably optional. That removing it is *sufficient* on its own is
a well-grounded inference rather than something proven by A/B test, since you
cannot reproduce a 16h expiry on a domain where you have already disabled the
policy. It is free and reversible, so it is the right thing to try first. If it
does not hold, escalate to the scoped binding above as a request to your admins.
`terraform/gws-project/session-control.tf.ADMIN-ONLY` is that request, written
out, ready to hand over.

## Terraform gotchas

**Quota project chicken-and-egg.** Cloud Identity and Access Context Manager calls
are org-scoped and carry no `project` attribute, so they need a quota-project
header. But putting `billing_project` and `user_project_override` on the *default*
provider makes the `google_project` creation call fail with a 400, because at that
moment the project does not exist. Put them on a **separate aliased provider** and
apply it only to the org-scoped resources.

**ADC hijacking.** Every stack uses whatever `gcloud auth application-default
login` last wrote. Running one stack repoints ADC, and the next stack then fails
with "caller does not have permission", which looks like a broken project but is a
hijacked identity. Check first:

```bash
curl -s "https://oauth2.googleapis.com/tokeninfo?access_token=$(gcloud auth application-default print-access-token)" | jq -r .email
```

**`roles/owner` cannot be granted to Workspace accounts via API**
(`SOLO_MUST_INVITE_OWNERS`). Use `roles/editor`.

**Console hotfix means same-day terraform reconcile.** If an outage forces a manual
change, the incident is not closed until the corrected terraform is applied and
`plan` is clean. A corrected `.tf` that was never applied is worse than nothing,
because it reads as done and the next person trusts it.

## Other quirks

**The keyring beats the exported file.** `gws` prefers its encrypted keyring
(`credentials.enc`) over `.credentials/<alias>.json`, so rewriting the exported
file alone does nothing. Run `refresh-gws-creds.sh` to push it back into the
keyring.

**Always pass the account alias.** Omitting it routes to the default, which
silently operates on the wrong mailbox.

**403 complaining about a quota project** usually means `project_id` in the
registry is the project *name* instead of the project *ID*. That value is sent as
the `x-goog-user-project` header.

**The Docs API needs Full Access**, not read-only, even for reads.

## Scripts

| Script | Does |
|---|---|
| `gws-multi.sh` | the wrapper. Routes any `gws` command to an account's isolated config dir |
| `gws-auth-setup.sh` | OAuth login for one or all accounts. Honors `scopes` / `--no-cloud-scopes` |
| `gws-check-scopes.sh` | mints a token and reports the scopes Google actually granted |
| `gws-distribute-accounts.sh` | copies relevant account entries into child project registries |
| `gws-install-binary.sh` | installs or updates the `gws` binary |
| `refresh-gws-creds.sh` | pushes exported credential files back into the keyring |
| `gws-healthcheck-alert.sh` | cron sweep, alerts (Slack optional, macOS notification) on token death |

Nothing here prints a token. `gws-check-scopes.sh` mints one to read its scope list
and deliberately never echoes it.
