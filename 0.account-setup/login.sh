#!/usr/bin/env bash
set -e

# Clear any existing credentials
unset GOOGLE_APPLICATION_CREDENTIALS

# Determine the correct config directory
if [[ -n "${CLOUD_SHELL}" ]]; then
  # Google Cloud Shell uses /home/${USER}/.config
  GCLOUD_CONFIG_DIR="${HOME}/.config/gcloud"
else
  # macOS and Linux both store under ~/.config/gcloud
  GCLOUD_CONFIG_DIR="${HOME}/.config/gcloud"
fi

# Authenticate for application default credentials (used by SDKs & Terraform)
gcloud auth application-default login

# Optional: also log into the gcloud CLI for interactive commands
sleep 3
gcloud auth login

# Set the environment variable dynamically
export GOOGLE_APPLICATION_CREDENTIALS="${GCLOUD_CONFIG_DIR}/application_default_credentials.json"

echo "Using GOOGLE_APPLICATION_CREDENTIALS=${GOOGLE_APPLICATION_CREDENTIALS}"

# Persist it for future sessions if not already there
PROFILE_FILE="$HOME/.bashrc"
[[ "$OSTYPE" == "darwin"* ]] && PROFILE_FILE="$HOME/.bash_profile"

if ! grep -q "GOOGLE_APPLICATION_CREDENTIALS" "$PROFILE_FILE"; then
  echo "export GOOGLE_APPLICATION_CREDENTIALS=\"${GOOGLE_APPLICATION_CREDENTIALS}\"" >> "$PROFILE_FILE"
  echo "✅ Added GOOGLE_APPLICATION_CREDENTIALS to $PROFILE_FILE"
fi

# Reload the profile for current shell
source "$PROFILE_FILE"
