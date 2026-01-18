.PHONY: help generate-configs bootstrap install-fleet check-health clean wake-edge-all

help: ## Show this help message
	@echo "Homelab Talos-OPNsense Management"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

check-prereqs: ## Check required tools are installed
	@echo "Checking prerequisites..."
	@command -v talosctl >/dev/null 2>&1 || { echo "Error: talosctl not found. Install from https://www.talos.dev/"; exit 1; }
	@command -v kubectl >/dev/null 2>&1 || { echo "Error: kubectl not found"; exit 1; }
	@command -v helm >/dev/null 2>&1 || { echo "Error: helm not found"; exit 1; }
	@echo "All prerequisites met!"

generate-configs: check-prereqs ## Generate Talos configurations from inventory
	@echo "Generating Talos configurations..."
	cd talos && ./generate.sh

bootstrap: check-prereqs ## Bootstrap the Kubernetes cluster
	@echo "Bootstrapping cluster..."
	cd talos && ./bootstrap.sh

install-fleet: ## Install Fleet GitOps
	@echo "Installing Fleet..."
	helm repo add fleet https://rancher.github.io/fleet-helm-charts/ || true
	helm repo update
	helm install fleet-crd fleet/fleet-crd -n cattle-fleet-system --create-namespace --wait || true
	helm install fleet fleet/fleet -n cattle-fleet-system --wait || true
	@echo "Fleet installed successfully!"

register-gitrepo: ## Register this Git repository with Fleet
	@echo "Registering Git repository..."
	@echo "Note: Update the repo URL in the command below"
	kubectl apply -f - <<EOF
	apiVersion: fleet.cattle.io/v1alpha1
	kind: GitRepo
	metadata:
	  name: homelab
	  namespace: fleet-default
	spec:
	  repo: https://github.com/bjoernellens1/homelab-talos-opnsense
	  branch: main
	  paths:
	  - fleet
	  targets:
	  - clusterSelector:
	      matchLabels:
	        cluster: homelab
	EOF
	@echo "Labeling cluster..."
	@CLUSTER_NAME=$$(kubectl get clusters.fleet.cattle.io -n fleet-default -o jsonpath='{.items[0].metadata.name}') && \
	kubectl label clusters.fleet.cattle.io -n fleet-default $$CLUSTER_NAME cluster=homelab --overwrite

check-health: ## Check cluster health status
	@echo "=== Cluster Nodes ==="
	@kubectl get nodes -o wide
	@echo ""
	@echo "=== Fleet Bundles ==="
	@kubectl get bundles -n fleet-default 2>/dev/null || echo "Fleet not yet installed"
	@echo ""
	@echo "=== Longhorn Status ==="
	@kubectl get pods -n longhorn-system 2>/dev/null || echo "Longhorn not yet installed"
	@echo ""
	@echo "=== Platform Components ==="
	@kubectl get pods -n kube-system -l app.kubernetes.io/name=cilium 2>/dev/null || echo "Cilium not yet installed"
	@kubectl get pods -n ingress-nginx 2>/dev/null || echo "Ingress not yet installed"
	@echo ""
	@echo "=== Monitoring ==="
	@kubectl get pods -n monitoring 2>/dev/null || echo "Monitoring not yet installed"

wake-edge-all: ## Wake all edge nodes via WoL
	@echo "Waking all edge nodes..."
	./scripts/wake-edge-nodes.sh all

wake-edge-%: ## Wake specific edge node (e.g., make wake-edge-01)
	@echo "Waking edge node $*..."
	./scripts/wake-edge-nodes.sh talos-edge-$*

get-kubeconfig: ## Display kubeconfig location
	@echo "KUBECONFIG is at: $(PWD)/talos/kubeconfig"
	@echo "Export it with: export KUBECONFIG=$(PWD)/talos/kubeconfig"

get-talosconfig: ## Display talosconfig location
	@echo "TALOSCONFIG is at: $(PWD)/talos/talosconfig"
	@echo "Export it with: export TALOSCONFIG=$(PWD)/talos/talosconfig"

view-grafana: ## Port-forward to Grafana
	@echo "Opening Grafana on http://localhost:3000"
	@echo "Username: admin"
	@echo "Password: changeme"
	kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

view-longhorn: ## Port-forward to Longhorn UI
	@echo "Opening Longhorn UI on http://localhost:8080"
	kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80

logs-fleet: ## View Fleet controller logs
	kubectl logs -n cattle-fleet-system -l app=fleet-controller -f

logs-talos: ## View Talos logs from first control plane node
	talosctl -n 10.0.0.11 logs controller-runtime -f

clean-configs: ## Remove generated Talos configurations (keeps secrets.yaml)
	@echo "Removing generated Talos configs..."
	@cd talos && find . -name "controlplane-*.yaml" -delete
	@cd talos && find . -name "worker-*.yaml" -delete
	@echo "Configs removed. secrets.yaml preserved."

clean-all: ## Remove all generated files including secrets (DANGEROUS)
	@echo "WARNING: This will remove all generated configurations including secrets!"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		cd talos && rm -f secrets.yaml controlplane-*.yaml worker-*.yaml talosconfig kubeconfig; \
		echo "All configs removed."; \
	fi

# Full deployment workflow
deploy-all: check-prereqs generate-configs bootstrap install-fleet register-gitrepo check-health ## Complete deployment from scratch
	@echo ""
	@echo "===================================="
	@echo "Deployment complete!"
	@echo "===================================="
	@echo ""
	@echo "Next steps:"
	@echo "1. Wait for all bundles to deploy: kubectl get bundles -n fleet-default -w"
	@echo "2. Check cluster health: make check-health"
	@echo "3. Access Grafana: make view-grafana"
	@echo "4. Access Longhorn: make view-longhorn"
