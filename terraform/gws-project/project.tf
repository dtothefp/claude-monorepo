locals {
  # org_id and folder_id are mutually exclusive on google_project. Prefer the
  # folder when one is given, because a corporate org that hands you a folder is
  # usually blocking creation at the org root.
  use_folder = var.folder_id != ""
}

resource "google_project" "gws" {
  name       = var.project_name
  project_id = var.project_id

  # Exactly one of these ends up set. The project lands inside the Workspace's org
  # either way, which is the whole point: Internal audience on the consent
  # screen is only selectable when the project belongs to the Workspace's org.
  org_id    = local.use_folder ? null : var.org_id
  folder_id = local.use_folder ? var.folder_id : null

  # No billing_account. Every API in var.gws_apis is free-tier. Attaching a
  # billing account would also mean attaching the EMPLOYER's billing account to a
  # project you created, which is a conversation you do not need to have.

  # auto_create_network defaults to true and spins up a default VPC with
  # firewall rules that some org policies forbid. This project never runs
  # compute, so skip it. Also avoids tripping constraints/compute.skipDefaultNetworkCreation.
  auto_create_network = false

  lifecycle {
    # The project is the anchor for the OAuth client. Recreating it invalidates
    # the client and every token minted from it, which means re-auth. Make that
    # an explicit decision rather than a side effect of an edited variable.
    prevent_destroy = true
  }
}

resource "google_project_service" "apis" {
  for_each = toset(var.gws_apis)

  project = google_project.gws.project_id
  service = each.value

  # Leave APIs on if the stack is destroyed. Disabling an API can break other
  # things in a shared org and is never what you want on teardown.
  disable_on_destroy = false

  depends_on = [google_project.gws]
}
