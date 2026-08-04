terraform {
  required_version = ">= 1.9"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
  # Local state. One-time setup, no CI/CD. terraform.tfstate is gitignored and
  # holds only GCP project metadata (no secrets).
}

# READ THIS BEFORE RUNNING.
#
# This stack is deliberately DIFFERENT from every other terraform-* stack in
# a Workspace you administer. Those sibling stacks
# were written for Workspace domains you SUPER-ADMIN. They kill the ~16h
# invalid_rapt clock with org-scoped resources: a Cloud Identity group plus a
# google_access_context_manager_gcp_user_access_binding.
#
# This targets an employer's Workspace, where you are a regular member, not a
# super-admin. He can create a project in the org and set the consent screen to
# Internal, but he can NOT:
#   - reach admin.google.com > Security > Google Cloud session control
#   - grant himself roles/accesscontextmanager.gcpAccessAdmin at the org
#   - create Cloud Identity groups
# So the entire admin playbook is unavailable here. Do not copy session-control.tf
# from a sibling stack into this directory and expect it to apply; it will 403.
#
# The no-admin lever is SCOPE SELECTION, not policy. Google Cloud session
# control applies its reauth (RAPT) clock to tokens that carry Google Cloud
# OAuth scopes. Our gws-auth-setup.sh has historically requested
# https://www.googleapis.com/auth/cloud-platform on every account, which opts
# the token into that clock. Gmail, Drive, Docs, Sheets, Calendar, Contacts,
# Tasks and Search Console all have their own scopes and need no Cloud scope at
# all (gws's own help calls cloud-platform part of `--full`). Authenticating
# this account WITHOUT cloud-platform is what keeps the token off the reauth
# clock without touching a single org policy.
#
# See README.md in this directory for the full rationale and the fallback if it
# turns out not to be enough.

provider "google" {
  # Uses gcloud application-default credentials, which MUST be the your employer
  # account, not your personal Gmail:
  #
  #   gcloud auth application-default login    # sign in as you@your-employer.com
  #
  # No billing_project / user_project_override on the default provider. Setting
  # a quota project globally puts the header on the google_project creation call
  # itself, which then 400s "project not found" because the project does not
  # exist yet. We hit this on a sibling stack; the fix
  # there was a separate aliased provider. This stack creates no org-scoped or
  # customer-scoped resources, so it needs no aliased provider at all.
  #
  # GOTCHA: this leaves the machine's ADC pointing at the work account. Every
  # other stack in this repo expects your personal ADC. If you ever run this from the
  # personal machine, re-run `gcloud auth application-default login` as
  # your personal identity afterwards. On a dedicated work machine this does not apply,
  # which is one more reason to keep the two machines separate.
}
