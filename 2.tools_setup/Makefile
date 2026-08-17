.PHONY: install-terraform build destroy count-pods-in-nodes get-argo-password get-sosivio-password

# Install Terraform only if it is not already installed.
install-terraform:
	@if ! command -v terraform >/dev/null 2>&1; then \
		echo "Terraform not found. Installing Terraform..."; \
		sudo apt-get update; \
		sudo apt-get install -y wget gpg lsb-release; \
		wget -qO- https://apt.releases.hashicorp.com/gpg | \
			sudo gpg --dearmor --yes -o /usr/share/keyrings/hashicorp-archive-keyring.gpg; \
		echo "deb [arch=$$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $$(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) main" | \
			sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null; \
		sudo apt-get update; \
		sudo apt-get install -y terraform; \
		echo "Terraform installed successfully."; \
	else \
		echo "Terraform already installed: $$(terraform version | head -n 1)"; \
	fi

# Build all tools.
build: install-terraform
	source ../scripts/setenv.sh && terraform apply -parallelism=3 -var-file ../0.account_setup/configurations.tfvars

# Find out list of pods in each worker node.
count-pods-in-nodes:
	for node in $$(kubectl get nodes | awk '{if (NR!=1) {print $$1}}'); do \
		echo ""; \
		echo "Checking $${node}..."; \
		kubectl describe node $${node} | grep "Non-terminated"; \
	done

# Get ArgoCD password to login.
get-argo-password:
	kubectl -n argocd get secret argocd-initial-admin-secret \
		-o jsonpath="{.data.password}" | base64 -d
	@echo

# Get Sosivio password to login.
get-sosivio-password:
	kubectl get secret -n sosivio sosivio-admin-otp \
		-o jsonpath='{.data.password}' | base64 -d
	@echo

# Destroy all tools.
destroy: install-terraform
	source ../scripts/setenv.sh && terraform destroy -var-file ../0.account_setup/configurations.tfvars