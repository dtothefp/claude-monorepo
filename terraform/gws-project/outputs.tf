output "project_id" {
  value = google_project.gws.project_id
}

output "project_number" {
  value = google_project.gws.number
}

output "console_consent_url" {
  description = "Direct link to the audience/consent screen page for this project."
  value       = "https://console.cloud.google.com/auth/audience?project=${google_project.gws.project_id}"
}

output "console_credentials_url" {
  description = "Direct link to the credentials page where the Desktop OAuth client is created."
  value       = "https://console.cloud.google.com/apis/credentials?project=${google_project.gws.project_id}"
}

output "next_steps" {
  value = <<-EOT

    Project ${google_project.gws.project_id} created inside the org, APIs enabled.

    Everything below is console + CLI work that has no Terraform resource.

    1. CONSENT SCREEN -> INTERNAL
       https://console.cloud.google.com/auth/audience?project=${google_project.gws.project_id}
       Audience: Internal. It should be selectable because the project lives in
       the Workspace's org. If it is greyed out with "Because you're not a Google
       Workspace user...", the project did NOT land in the org. Do not work
       around it by choosing External. Destroy and recreate with the right
       org_id/folder_id, because a project's org is fixed at creation.
       Internal needs no publishing, no verification, no unverified-app warning,
       and has no 7-day token TTL.

    2. DESKTOP OAUTH CLIENT
       https://console.cloud.google.com/apis/credentials?project=${google_project.gws.project_id}
       Create credentials > OAuth client ID > Application type: DESKTOP APP.
       Not "Web application" (the gws CLI uses the installed-app loopback flow).
       Download JSON.

    3. SAVE THE CLIENT
       .credentials/client_secret_work.json
       Google writes the project NAME into installed.project_id, not the ID.
       gws-auth-setup.sh rewrites it to ${google_project.gws.project_id} on
       capture, so you do not have to. If you ever see a 403 about "Service
       Usage Consumer", that field is the usual culprit.

    4. REGISTER THE ACCOUNT
       Add to .gws-accounts.json:

         "work": {
           "email": "${var.workspace_account}",
           "credential_file": ".credentials/work.json",
           "client_secret_file": ".credentials/client_secret_work.json",
           "project_id": "${google_project.gws.project_id}",
           "description": "your employer work account. Internal app in the Workspace's org.",
           "scopes": "workspace-no-cloud",
           "projects": []
         }

       The "scopes": "workspace-no-cloud" line is the important one and is the
       whole reason this account should not hit the ~16h invalid_rapt clock.
       It tells gws-auth-setup.sh to request the Workspace scopes WITHOUT
       https://www.googleapis.com/auth/cloud-platform. Google Cloud session
       control applies its reauth clock to tokens carrying Cloud scopes, and
       you cannot change that policy as a regular org member. So do not carry
       the scope.

    5. AUTHENTICATE
       ./scripts/gws/gws-auth-setup.sh --account work

       Confirm the grant came back WITHOUT a Cloud scope:
       ./scripts/gws/gws-check-scopes.sh work

    6. VERIFY
       ./scripts/gws/gws-multi.sh work gmail users getProfile --params '{"userId":"me"}'

    IF invalid_rapt SHOWS UP ANYWAY (give it 48h of real use to prove it):
       Read README.md, "If scope trimming is not enough". Short version: the
       remaining fix is org-admin-only, so it becomes a request to your Workspace admins,
       and the README has the exact wording plus the terraform they would apply.
  EOT
}
