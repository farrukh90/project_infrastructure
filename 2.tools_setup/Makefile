# Build all tools.
build:
	source ../scripts/setenv.sh && terraform apply -var-file ../0.account_setup/configurations.tfvars 

# Find out list of pods in each worker node.
count-pods-in-nodes:
	for node in $$(kubectl get nodes | awk '{if (NR!=1) {print $$1}}'); do echo ""; echo "Checking $${node}..."; kubectl describe node $${node} | grep "Non-terminated" ; done

# Get argocd password to login.
get-argo-password:
	kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Get sosivio password to login.
get-sosivio-password:
	kubectl get secret -n sosivio sosivio-admin-otp -o jsonpath='{.data.password}' | base64 -d

# Destroy all tools.
destroy:
	source ../scripts/setenv.sh && terraform apply -var-file ../0.account_setup/configurations.tfvars 
