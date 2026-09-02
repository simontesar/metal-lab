CLAB     ?= clab
TOPO     ?= infra.clab.yaml
LAB_NAME ?= metal-operator-test
DISK_SIZE ?= 20G
NODES    ?= node1 node2
VM_DIR   ?= vm

KUBECONFIG ?= $(CURDIR)/kubeconfig.yaml
KUSTOMIZE  ?= kustomize
KUBECTL    ?= kubectl
BMC_STACK ?= kustomization/bmc

METAL_OPERATOR_STACK ?= kustomization/metal-operator
BOOT_OPERATOR_STACK ?= kustomization/boot-operator
FEDHCP_STACK ?= kustomization/fedhcp
TFTP_STACK ?= kustomization/tftp
CERT_MANAGER_VERSION ?= v1.17.1
CERT_MANAGER_MANIFEST ?= https://github.com/cert-manager/cert-manager/releases/download/$(CERT_MANAGER_VERSION)/cert-manager.yaml
KIND_CLUSTER_NAME ?= k8s
TFTP_IMG ?= tftp:latest
KBAKE_KERNEL_TAG        ?= v7.1
METALPROBE_IMAGE_NAME   ?= ghcr.io/simontesar/metal-lab
METALPROBE_IMAGE_TAG    ?= dev

.PHONY: help deploy destroy clean-disks inspect \
	cert-manager-install cert-manager-wait \
	metal-operator-deploy metal-operator-delete \
	metal-operator-deploy-wait \
	boot-operator-deploy boot-operator-delete \
	boot-operator-deploy-wait \
	fedhcp-deploy fedhcp-delete fedhcp-deploy-wait \
	tftp-images tftp-deploy tftp-delete tftp-deploy-wait \
	bmc-apply bmc-delete \
	metalprobe-image-tools metalprobe-image-build metalprobe-image-push \
	node1-console node2-console

help: ## Show available targets
	@grep -E '^[a-zA-Z0-9_.-]+:.*##' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*## "}; {printf "  %-24s %s\n", $$1, $$2}'

deploy: ## Create disks and deploy lab
	touch $(KUBECONFIG) # Initialises the kubeconfig with users' permissions
	$(CLAB) deploy -t $(TOPO)

destroy: ## Tear down the lab
	$(CLAB) destroy -t $(TOPO) --cleanup

clean-disks: ## Remove per-node VM disks, OVMF_VARS and console logs
	@for node in $(NODES); do \
		rm -f $(VM_DIR)/$$node/disk.qcow2 \
			$(VM_DIR)/$$node/OVMF_VARS.fd \
			$(VM_DIR)/$$node/console.log; \
	done

inspect: ## Show lab status
	$(CLAB) inspect -t $(TOPO)

node1-console: ## Follow node1's serial console
	tail -n +1 -F $(VM_DIR)/node1/console.log

node2-console: ## Follow node2's serial console
	tail -n +1 -F $(VM_DIR)/node2/console.log

cert-manager-install: ## Install cert-manager from upstream release manifest
	KUBECONFIG=$(KUBECONFIG) $(KUBECTL) apply -f $(CERT_MANAGER_MANIFEST)

cert-manager-wait: ## Wait for cert-manager deployments to become available
	@until KUBECONFIG=$(KUBECONFIG) $(KUBECTL) get ns cert-manager >/dev/null 2>&1; do \
		echo "Waiting for cert-manager namespace..."; sleep 5; \
	done
	KUBECONFIG=$(KUBECONFIG) $(KUBECTL) wait --for=condition=Available \
		deployment/cert-manager -n cert-manager --timeout=300s
	KUBECONFIG=$(KUBECONFIG) $(KUBECTL) wait --for=condition=Available \
		deployment/cert-manager-webhook -n cert-manager --timeout=300s
	KUBECONFIG=$(KUBECONFIG) $(KUBECTL) wait --for=condition=Available \
		deployment/cert-manager-cainjector -n cert-manager --timeout=300s

metal-operator-deploy: ## Deploy metal-operator via kustomize overlay
	KUBECONFIG=$(KUBECONFIG) $(KUSTOMIZE) build $(METAL_OPERATOR_STACK) | \
		KUBECONFIG=$(KUBECONFIG) $(KUBECTL) apply -f -

metal-operator-delete: ## Delete metal-operator kustomize overlay
	KUBECONFIG=$(KUBECONFIG) $(KUSTOMIZE) build $(METAL_OPERATOR_STACK) | \
		KUBECONFIG=$(KUBECONFIG) $(KUBECTL) delete -f - --ignore-not-found

metal-operator-deploy-wait: ## Install cert-manager and metal-operator, then wait
metal-operator-deploy-wait: cert-manager-install cert-manager-wait \
	metal-operator-deploy
	@until KUBECONFIG=$(KUBECONFIG) $(KUBECTL) get ns metal-operator-system >/dev/null 2>&1; do \
		echo "Waiting for metal-operator-system namespace..."; sleep 5; \
	done
	@until KUBECONFIG=$(KUBECONFIG) $(KUBECTL) -n metal-operator-system \
		get deploy metal-operator-controller-manager >/dev/null 2>&1; do \
		echo "Waiting for metal-operator deployment..."; sleep 5; \
	done
	KUBECONFIG=$(KUBECONFIG) $(KUBECTL) wait --for=condition=Available \
		deployment/metal-operator-controller-manager \
		-n metal-operator-system --timeout=600s

boot-operator-deploy: ## Deploy boot-operator via kustomize overlay
	KUBECONFIG=$(KUBECONFIG) $(KUSTOMIZE) build $(BOOT_OPERATOR_STACK) | \
		KUBECONFIG=$(KUBECONFIG) $(KUBECTL) apply -f -

boot-operator-delete: ## Delete boot-operator kustomize overlay
	KUBECONFIG=$(KUBECONFIG) $(KUSTOMIZE) build $(BOOT_OPERATOR_STACK) | \
		KUBECONFIG=$(KUBECONFIG) $(KUBECTL) delete -f - --ignore-not-found

boot-operator-deploy-wait: ## Deploy boot-operator (after metal-operator), then wait
boot-operator-deploy-wait: metal-operator-deploy-wait \
	boot-operator-deploy
	@until KUBECONFIG=$(KUBECONFIG) $(KUBECTL) get ns boot-operator-system >/dev/null 2>&1; do \
		echo "Waiting for boot-operator-system namespace..."; sleep 5; \
	done
	@until KUBECONFIG=$(KUBECONFIG) $(KUBECTL) -n boot-operator-system \
		get deploy boot-operator-controller-manager >/dev/null 2>&1; do \
		echo "Waiting for boot-operator deployment..."; sleep 5; \
	done
	KUBECONFIG=$(KUBECONFIG) $(KUBECTL) wait --for=condition=Available \
		deployment/boot-operator-controller-manager \
		-n boot-operator-system --timeout=600s

fedhcp-deploy: ## Deploy FeDHCP via kustomize overlay
	KUBECONFIG=$(KUBECONFIG) $(KUSTOMIZE) build $(FEDHCP_STACK) | \
		KUBECONFIG=$(KUBECONFIG) $(KUBECTL) apply -f -

fedhcp-delete: ## Delete FeDHCP kustomize overlay
	KUBECONFIG=$(KUBECONFIG) $(KUSTOMIZE) build $(FEDHCP_STACK) | \
		KUBECONFIG=$(KUBECONFIG) $(KUBECTL) delete -f - --ignore-not-found

fedhcp-deploy-wait: ## Deploy FeDHCP (after TFTP), then wait
fedhcp-deploy-wait: tftp-deploy-wait \
	fedhcp-deploy
	@until KUBECONFIG=$(KUBECONFIG) $(KUBECTL) get ns fedhcp-system >/dev/null 2>&1; do \
		echo "Waiting for fedhcp-system namespace..."; sleep 5; \
	done
	@until KUBECONFIG=$(KUBECONFIG) $(KUBECTL) -n fedhcp-system \
		get deploy fedhcp >/dev/null 2>&1; do \
		echo "Waiting for fedhcp deployment..."; sleep 5; \
	done
	KUBECONFIG=$(KUBECONFIG) $(KUBECTL) wait --for=condition=Available \
		deployment/fedhcp \
		-n fedhcp-system --timeout=300s

tftp-images: ## Build and load the TFTP (iPXE chainload) image into Kind
	docker build -t $(TFTP_IMG) $(TFTP_STACK)
	kind load docker-image $(TFTP_IMG) \
		--name $(KIND_CLUSTER_NAME)

tftp-deploy: ## Deploy TFTP server via kustomize overlay
	KUBECONFIG=$(KUBECONFIG) $(KUSTOMIZE) build $(TFTP_STACK) | \
		KUBECONFIG=$(KUBECONFIG) $(KUBECTL) apply -f -

tftp-delete: ## Delete TFTP server kustomize overlay
	KUBECONFIG=$(KUBECONFIG) $(KUSTOMIZE) build $(TFTP_STACK) | \
		KUBECONFIG=$(KUBECONFIG) $(KUBECTL) delete -f - --ignore-not-found

tftp-deploy-wait: ## Deploy TFTP server (after boot-operator), then wait
tftp-deploy-wait: boot-operator-deploy-wait \
	tftp-images tftp-deploy
	@until KUBECONFIG=$(KUBECONFIG) $(KUBECTL) get ns tftp-system >/dev/null 2>&1; do \
		echo "Waiting for tftp-system namespace..."; sleep 5; \
	done
	@until KUBECONFIG=$(KUBECONFIG) $(KUBECTL) -n tftp-system \
		get deploy tftp >/dev/null 2>&1; do \
		echo "Waiting for tftp deployment..."; sleep 5; \
	done
	KUBECONFIG=$(KUBECONFIG) $(KUBECTL) wait --for=condition=Available \
		deployment/tftp \
		-n tftp-system --timeout=300s

bmc-apply: ## Apply BMC + BMCSecret for node1 and node2
	KUBECONFIG=$(KUBECONFIG) $(KUSTOMIZE) build $(BMC_STACK) | \
		KUBECONFIG=$(KUBECONFIG) $(KUBECTL) apply -f -

bmc-delete: ## Delete BMC + BMCSecret for node1 and node2
	KUBECONFIG=$(KUBECONFIG) $(KUSTOMIZE) build $(BMC_STACK) | \
		KUBECONFIG=$(KUBECONFIG) $(KUBECTL) delete -f - --ignore-not-found

metalprobe-image-tools: ## Install u-root, ironcore-image, and kbake
	cd metalprobe-image && go install github.com/u-root/u-root@v0.16.0
	cd metalprobe-image && go install github.com/ironcore-dev/ironcore-image/cmd/ironcore-image@v0.5.0
	cd metalprobe-image && go install github.com/ironcore-dev/kbake@5ec65c0d5d780e4a2c36c736c3684314c16250e6

metalprobe-image-build: metalprobe-image-tools ## Build the metalprobe u-root boot image (kernel+initramfs)
	cd metalprobe-image && ./hack/build.sh -k "$(KBAKE_KERNEL_TAG)" -o ./bin/initramfs.cpio
	cd metalprobe-image && ironcore-image build --tag "$(METALPROBE_IMAGE_NAME):$(METALPROBE_IMAGE_TAG)" \
		--config "arch=amd64,initramfs=./bin/initramfs.cpio,kernel=./bin/vmlinuz"

metalprobe-image-push: ## Push the built metalprobe boot image (requires ghcr.io auth)
	cd metalprobe-image && ironcore-image push "$(METALPROBE_IMAGE_NAME):$(METALPROBE_IMAGE_TAG)"
