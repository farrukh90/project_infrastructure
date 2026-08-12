
# 0.account_setup instructions

----
### Step 1
#### Please navigate to https://console.cloud.google.com

----
### Step 2

#### Login with your brand new account
#### Search for "Create a Project" Tab
<br>

#### Create new project and call it:
```
terraform-project-WHATEVER_YOU_WANT
```
It should start with `terraform-project`

#### Navigate to Cloud Storage, and create a bucket named:
```
terraform-project-WHATEVER_YOU_WANT
```
It should start with `terraform-project`
It should be inside the project you created in step2

----
### Step 3
#### Create a new file here called:
```
0.account_setup/configurations.tfvars
```
#### and add the following message there
```
# Please get your AWS Domain
dns_name = "AWS_DOMAIN"

# Use GCP account gmail
email              = "GMAIL"

# Add bucketname you created above
bucket_name        = "terraform-project-WHATEVER_YOU_WANT"

# Add project id of the project
# Keep in mind, ID not the name
project_id         = "PROJECT_NAME-NUMBERS"
```
#### Here's the location of the projects https://console.cloud.google.com/cloud-resource-manager

----
### Step 4
Go to your terminal and type this command in `0.account_setup`:
```
bash login.sh
```
#### And follow the instructions. It asks you to login 2 times, please click the link on each request and paste the code into the terminal to proceed.
----


### To enable services, please add the below code into 0.account_setup/configurations.tfvars and set service to "true"
#### Example:
```
# List of services to activate
kube-prometheus-stack   = false
argo                    = false
datadog                 = false
jenkins                 = false
sosivio                 = false
sumologic               = false
vault                   = false
sftpgo                  = false
ots                     = false
rancher                 = false
elasticsearch           = false
ghrunner                = false
mlflow                  = false
zipkin                  = false
istio                   = false
jaeger                  = false
gitlab                  = false
kyverno                 = false
blackbox                = false
alertmanager            = false
velero                  = false
loki                    = false
atlantis                = false
kagent                  = true

# Configuring datadog DO NOT CONTINUE. WE WILL WORK IN CLASS
datadog-config = {
    deployment_name = "datadog"
    apiKey          = ""
    site            = "us5.datadoghq.com"
    cpu_requests    = "200m"
    memory_requests = "256Mi"
    cpu_limits      = "500m"
    memory_limits   = "1024Mi"
}
```

## Needed for blackbox and prometheus
### Sends a slack message
```
slack_api_url = "https://hooks.slack.com/"

```
### Monitors these urls
```
blackbox_targets = [
    "https://www.google.com",
    "https://www.bing.com",
    "https://yahoos.com"        # intentionally wrong
]
```
### Specify the repeat interval of message in slack
```
repeat_interval = "1m"
```
