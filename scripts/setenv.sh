#!/bin/bash

# Set current folder
DIR=$(pwd)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_INFRA_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_FILE="${PROJECT_INFRA_DIR}/0.account_setup/configurations.tfvars"
BIN_DIR="${PROJECT_INFRA_DIR}/bin"

### Set color
red=$(tput setaf 1)
green=$(tput setaf 2)
reset=$(tput sgr0)

#########################################################################################################
if [ "$GOOGLE_APPLICATION_CREDENTIALS" = "$HOME/.config/gcloud/application_default_credentials.json" ]; then
  unset GOOGLE_APPLICATION_CREDENTIALS
fi

if [ ! -f "$HOME/.config/gcloud/application_default_credentials.json" ]; then
  echo "${red}Application Default Credentials (ADC) not found.${reset}"
  echo "${green}Running 'gcloud auth application-default login'...${reset}"
  gcloud auth application-default login --no-launch-browser
fi

#########################################################################################################
# Check if the configurations.tfvars file is created
if [ -f "$CONFIG_FILE" ]; then
  echo ${green} "Please continue" ${reset}
else
  echo """

          ${red}Please create this file first $CONFIG_FILE ${reset}

  """
  return
fi

#########################################################################################################
project_id=$(cat "$CONFIG_FILE" | grep project_id | awk '{print $3}' | tr -d '"')
if [ -z $project_id ]; then
  echo """
      ${red}Did you add project name in $CONFIG_FILE  ${reset}

      project_id=YOUR_project_id
      """
  return
else
  echo ${green} "Project ID is given" ${reset}
fi

#########################################################################################################
bucket_name=$(cat "$CONFIG_FILE" | grep bucket_name | awk '{print $3}' | tr -d '"')
if [ -z $bucket_name ]; then
  echo """
      ${red}Did you add bucket_name  in $CONFIG_FILE  ${reset}

      bucket_name=YOUR_bucket_name
      """
  return
else
  echo ${green} "Bucket name is given" ${reset}
fi

# #########################################################################################################
# # Check if tfenv has version 1.5.0 installed
# COMMAND="tfenv"
# if ! command -v $COMMAND 2>/dev/null ;
# then
#     echo "${red}tfenv is not installed. Installing now...${reset}"
#     rm -rf ~/.tfenv
#     git clone --depth=1 https://github.com/tfutils/tfenv.git ~/.tfenv
#     echo 'export PATH="$HOME/.tfenv/bin:$PATH"' >> ~/.bash_profile
#     echo 'export PATH=$PATH:$HOME/.tfenv/bin' >> ~/.bashrc
#     mkdir -p $HOME/bin
#     ln -s ~/.tfenv/bin/* $HOME/bin
# else
#     echo "${green}tfenv ${reset}v1.5.0 ${green}is already installed.${reset}"
# fi
#########################################################################################################
# TFCOMMAND="terraform"
# if ! command -v $TFCOMMAND  2>/dev/null ;
# then
#     echo "${red}Terraform is not installed. Installing now...${reset}"
#     $HOME/bin/tfenv install 1.5.0
#     $HOME/bin/tfenv use 1.5.0
# else
#     echo "${green}Terraform ${reset}is already installed."
# fi

#########################################################################################################

gcloud config set project $project_id

################################################################################################################
#
#
#            This line below configures hashicorp vault cli
#
################################################################################################################
if [ ! -f "${BIN_DIR}/vault" ]; then
  echo """

${green}Configuring vault cli ${reset}

      """
  wget -q https://releases.hashicorp.com/vault/1.14.0/vault_1.14.0_linux_amd64.zip -P "$BIN_DIR"
  unzip -q "${BIN_DIR}/vault_1.14.0_linux_amd64.zip" -d "$BIN_DIR/"
  rm -rf "${BIN_DIR}/vault_1.14.0_linux_amd64.zip"
  export PATH="$PATH:$BIN_DIR"
  echo """

${green}vault is ready ${reset}

      """
fi

cat <<EOF >"$DIR/backend.tf"
terraform {
  backend "gcs" {
    bucket = "${bucket_name}"
    prefix = "$(pwd | sed "s|$HOME/||")"
  }
}
EOF
cat "$DIR/backend.tf"

export GOOGLE_PROJECT="$project_id"

terraform init -reconfigure

echo """
      Your Project ID: ${green}$project_id${reset}



      ${green}You are good to go !!! ${reset}


"""
