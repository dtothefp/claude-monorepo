# The account that runs terraform is the project creator and is therefore
# already owner. This grant is redundant for that identity, and it exists only
# so the binding is tracked in state rather than being invisible console-side
# drift. It is also what makes the project usable if your Workspace admins ends up creating
# the project on your behalf (in which case THEY are creator, not you).
#
# roles/editor rather than roles/owner on purpose: granting owner to a Workspace
# account through the API trips SOLO_MUST_INVITE_OWNERS / SOLO_REQUIRE_TOS_ACCEPTOR.
# We hit that on the shared stack in April. editor carries
# serviceusage.services.use, which is the permission that actually matters here,
# because that is what lets the account send x-goog-user-project and have Google
# honor it. Nothing about the reauth behavior depends on the IAM role.
resource "google_project_iam_member" "account_editor" {
  project = google_project.gws.project_id
  role    = "roles/editor"
  member  = "user:${var.workspace_account}"

  depends_on = [google_project.gws]
}
