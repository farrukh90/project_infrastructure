#######################################
#### Project wide  configuration
#######################################
# Please get your AWS Domain
dns_name = "awsprojectxconsulting.net"

# Use GCP account gmail
email = "farrukhsadykov7@gmail.com"

# Add bucketname you created above
bucket_name = "terraform-project-farrukh90"

# Add project id of the project
# Keep in mind, ID not the name
project_id = "terraform-project-504523"


#######################################
#### GKE Cluster configuration
#######################################
gke_config = {
  cluster_name   = "project-cluster"
  location       = "us-central1"
  node_count     = 1
  min_node_count = 1
  max_node_count = 10
  machine_type   = "e2-medium"
  disk_size_gb   = "50"
  disk_type      = "pd-balanced"
}

node_locations = [
  "us-central1-a",
  "us-central1-b",
  "us-central1-c",
]


#######################################
#### Enable and disable services
#######################################
ingress    = true
vault      = true
grafana    = true
prometheus = true
vpn        = true # careful with enabling. it will change the records of each application
