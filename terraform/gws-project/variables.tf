variable "project_id" {
  description = "GCP project ID that will own the OAuth desktop client for the work account. Must be globally unique across all of GCP and <= 30 chars."
  type        = string
  default     = "gws-work"

  validation {
    condition     = length(var.project_id) <= 30
    error_message = "GCP project IDs are capped at 30 characters."
  }
}

variable "project_name" {
  description = "Human-readable project name shown in the GCP console."
  type        = string
  default     = "GWS Work"
}

# NO DEFAULT ON PURPOSE. Guessing the org or the email is how you create an
# org-less project and lose the Internal consent screen permanently (a project's
# org is fixed at creation and cannot be moved later without org-admin help).
variable "org_id" {
  description = <<-EOT
    The Workspace's Cloud Identity organization ID (bare numeric, no "organizations/" prefix).

    The project MUST be created inside this org, or the OAuth consent screen will
    not offer the Internal audience and you are back to External + unverified-app
    warnings + a 7-day token TTL.

    Find it, signed in as your work account:
      gcloud organizations list

    If that returns 0 items, your work account cannot see the org and you need
    your Workspace admins to either grant you roles/resourcemanager.projectCreator on the org
    (or on a folder, see folder_id) or create the project for you.
  EOT
  type        = string
}

variable "folder_id" {
  description = <<-EOT
    Optional folder to create the project under (bare numeric, no "folders/" prefix).

    Leave empty to create directly under the org. Many corporate orgs use an org
    policy that blocks project creation at the org root and instead grants
    projectCreator on a specific sandbox/personal folder. If your Workspace admins tells you
    "create it under folder X", put X here. Setting folder_id and org_id together
    is invalid; when folder_id is set, org_id is used only for documentation and
    the folder determines placement.

    Find folders you can see:
      gcloud resource-manager folders list --organization=<org_id>
  EOT
  type        = string
  default     = ""
}

variable "workspace_account" {
  description = <<-EOT
    Your full Workspace email, e.g. you@your-employer.com.

    This is the account that runs terraform (its ADC), owns the project as
    creator, and later authenticates through gws-auth-setup.sh. Explicitly NOT
    your personal Gmail. No default, because a wrong value here silently grants
    editor to the wrong principal.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[^@]+@[^@]+\\.[^@]+$", var.workspace_account))
    error_message = "workspace_account must be a full email address."
  }
}

variable "gws_apis" {
  description = <<-EOT
    APIs enabled on the project. All free-tier, so no billing account is needed.

    Deliberately does NOT include cloudidentity.googleapis.com or
    accesscontextmanager.googleapis.com. Those exist in the sibling admin stacks
    to build the no-reauth binding, which a regular org member cannot create.
    Enabling them here would just fail or mislead the next reader.
  EOT
  type        = list(string)
  default = [
    "gmail.googleapis.com",
    "drive.googleapis.com",
    "docs.googleapis.com",
    "sheets.googleapis.com",
    "calendar-json.googleapis.com",
    "people.googleapis.com",
    "tasks.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "serviceusage.googleapis.com",
  ]
}
