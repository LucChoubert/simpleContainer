DOCKER       := podman
APPNAME      := simpleapp
IMAGE        := lucchoubert/simpleapp
TAGDEV       := latest
#TAG          := $(shell git log -1 --pretty=%h)
TAG          := $(shell if [ -d .git ]; then git log -1 --pretty=%h; else echo latest; fi)
PWD          := $(shell pwd)


######################################
# Virtual env & VM
######################################

.PHONY: install_virtualenv_dev
install_virtualenv_dev:
	rm -rf .venv __pycache__
	python3 -m venv .venv
	. .venv/bin/activate; pip3 install -r ./src/requirements.txt

.PHONY: run_virtualenv_dev
run_virtualenv_dev:
	. .venv/bin/activate; python3 -B -m flask --app ./src/app --debug run --host=0.0.0.0

.PHONY: clean_virtualenv_dev
clean_virtualenv_dev:
	rm -rf .venv __pycache__

#The first following line of the target is to use the repo default script when the os does not provide this script
.PHONY: build_artifact
build_vm_prd:
	$(eval WRITE-MIME-MULTIPART := $(shell [ -z `which write-mime-multipart` ] && echo "virtualmachine/write-mime-multipart.default"  || echo `which write-mime-multipart` ))
	@echo "*************************************"
	@echo "* Build tarball artifact            *"
	@echo "*************************************"
	rm -f virtualmachine/$(APPNAME).tar.gz virtualmachine/install.sh
	tar -czf virtualmachine/$(APPNAME).tar.gz ./src/backend ./src/frontend
	./virtualmachine/addpayload.sh --base64 virtualmachine/$(APPNAME).tar.gz
	echo $(WRITE-MIME-MULTIPART)
	$(WRITE-MIME-MULTIPART) --output ./virtualmachine/combined-userdata.mime ./virtualmachine/cloud-init-centos.yaml:text/cloud-config ./virtualmachine/install.sh:text/x-shellscript
	rm -f virtualmachine/$(APPNAME).tar.gz virtualmachine/install.sh

.PHONY: run_vm_prd
run_vm_prd:
	@echo "*************************************"
	@echo "* Starting VM on azure              *"
	@echo "*************************************"
	az vm list
	az vm create --resource-group myResourceGroup \
				 --name vmApp \
				 --priority Spot \
				 --image OpenLogic:CentOS:8_5:latest \
				 --custom-data ./virtualmachine/combined-userdata.mime \
				 --ssh-key-values ~/.ssh/cloud/ssh-key-for-cloud.key.pub \
				 --public-ip-sku standard \
				 --nic-delete-option delete \
				 --os-disk-delete-option delete \
				 --public-ip-address-dns-name mandelbrotinthecloud
	az network nsg rule create --resource-group myResourceGroup \
							   --nsg-name vmAppNSG \
							   --name AllowHttpInbound \
							   --priority 1050 \
							   --destination-port-ranges 80 \
							   --access Allow \
							   --protocol Tcp \
							   --description "Allow standard http traffic on port 80 to any IP address"
	az vm list

.PHONY: delete_vm_prd
delete_vm_prd:
	@echo "*************************************************"
	@echo "* Deleting VM & associated ressources on azure  *"
	@echo "*************************************************"
	az vm list
	az vm delete --resource-group myResourceGroup \
				 --name vmApp \
				 --yes
	az network nic delete --resource-group myResourceGroup \
				 				--name vmAppNetInt
	az network public-ip delete --resource-group myResourceGroup \
				 				--name vmAppPublicIP
	az network vnet delete --resource-group myResourceGroup \
				 		   --name vmAppVNET
	az network nsg delete --resource-group myResourceGroup \
						  --name vmAppNSG
	az vm list


######################################
# Containers
######################################

.PHONY: all_dev
all_dev: build_dev run_dev

.PHONY: all_prd
all_prd: build_prd run_prd

.PHONY: build_dev
build_dev:
	$(DOCKER) build --target DEV -t $(IMAGE)-dev:$(TAGDEV) -f Containerfile .
 
.PHONY: run_dev
run_dev:
	@echo "***************************************************************************"
	@echo "* You can test the code via command: curl http://localhost:5000           *"
	@echo "* Just update the sources and code will automatically reload              *"
	@echo "***************************************************************************"
	$(DOCKER) run -it --rm --mount type=bind,source=$(PWD)/src/,target=/app -p 5000:5000 $(IMAGE)-dev


.PHONY: build_prd
build_prd:
	$(DOCKER) build --target PRD -t $(IMAGE):$(TAGDEV) -f Containerfile .

.PHONY: run_prd
run_prd:
	@echo "************************************************************"
	@echo "* Starting the application as a pod                        *"
	@echo "*   - podman pod ls: to list the pod                       *"
	@echo "*   - podman ps: to list containers                        *"
	@echo "*   - podman logs $(IMAGE): to get container logs   *"
	@echo "************************************************************"
	$(DOCKER) pod create -p 8080:80 --name $(APPNAME)
	$(DOCKER) run --pod $(APPNAME) -d $(IMAGE)
	#$(DOCKER) play kube containers/MandelbrotAppPod.yaml
	@echo "************************************************************************"
	@echo "* You can access the app via: curl http://localhost:8080               *"
	@echo "************************************************************************"

.PHONY: clean_prd
clean_prd:
	$(DOCKER) pod stop $(APPNAME)
	$(DOCKER) pod rm $(APPNAME)

.PHONY: clean_images
clean_images:
	$(DOCKER) image rm -f ${IMAGE}-dev:latest
	$(DOCKER) image rm -f ${IMAGE}:latest

.PHONY: clean_containers
clean_containers:
	$(DOCKER) rm `$(DOCKER) ps -a | grep "Exited " | cut -f 1`


######################################
# Run in Azure 
######################################

.PHONY: run_cloud_aca_prd
run_cloud_aca_prd:
	@echo "*************************************"
	@echo "* Deploying Container on azure ACA  *"
	@echo "*************************************"
	@$(DOCKER) push ${IMAGE}
	az containerapp up \
	--subscription sbx-lchoubert3 \
	--location westeurope \
  	--name $(APPNAME) \
  	--resource-group $(APPNAME)-rg \
  	--environment 'my-container-apps' \
  	--image docker.io/lucchoubert/simpleapp:latest \
  	--target-port 8080 \
  	--ingress external \
  	--query properties.configuration.ingress.fqdn

#Following does not work for that project
.PHONY: run_cloud_vm_prd
run_cloud_vm_prd:
	@echo "*************************************"
	@echo "* Starting VM on azure              *"
	@echo "*************************************"
	@$(DOCKER) push ${IMAGE}
	@$(DOCKER) push ${IMAGEFRONT}
	az vm list
	az vm create --resource-group myResourceGroup \
				 --name vmApp \
				 --priority Spot \
				 --image OpenLogic:CentOS:8_5:latest \
				 --custom-data ./containers/cloud-init-centos.yaml \
				 --ssh-key-values ~/.ssh/cloud/ssh-key-for-cloud.key.pub \
				 --public-ip-sku standard \
				 --nic-delete-option delete \
				 --os-disk-delete-option delete \
				 --public-ip-address-dns-name mandelbrotinthecloud
	az network nsg rule create --resource-group myResourceGroup \
							   --nsg-name vmAppNSG \
							   --name AllowHttpInbound \
							   --priority 1050 \
							   --destination-port-ranges 80 \
							   --access Allow \
							   --protocol Tcp \
							   --description "Allow standard http traffic on port 80 to any IP address"
	az vm list


######################################
# IaC
######################################

.PHONY: provision_iac_prd
provision_iac_prd:
	@echo "*************************************"
	@echo "* Starting Infra on azure with Code *"
	@echo "*************************************"
	az vm list
	az deployment group create  --resource-group myResourceGroup \
	    						--template-file "./IaC/main.bicep" \
								--parameters @./IaC/main.parameters.json
	az vm list

.PHONY: run_iac_prd
run_iac_prd:
	@echo "*************************************"
	@echo "* Run container on azure Remote     *"
	@echo "*************************************"
	$(DOCKER) -r --url ssh://app@mandelbrotinthecloud.northeurope.cloudapp.azure.com:22/run/podman/podman.sock --identity ~/.ssh/cloud/ssh-key-for-cloud-ed25519.key info
	$(DOCKER) -r --url ssh://app@mandelbrotinthecloud.northeurope.cloudapp.azure.com:22/run/podman/podman.sock --identity ~/.ssh/cloud/ssh-key-for-cloud-ed25519.key play kube ./containers/MandelbrotAppPod.yaml
	$(DOCKER) -r --url ssh://app@mandelbrotinthecloud.northeurope.cloudapp.azure.com:22/run/podman/podman.sock --identity ~/.ssh/cloud/ssh-key-for-cloud-ed25519.key ps


######################################
# Utility Targets
######################################

.PHONY: login
dockerio_login:
	$(DOCKER) log -u ${DOCKER_USER} -p ${DOCKER_PASS}

.PHONY: az_sub
az_sub:
	az account set --subscription sbx-lchoubert3
	az account show

.PHONY: getip
getip:
	$(eval VMIP  := $(shell az vm show -d -g myResourceGroup -n vmApp --query publicIps -o tsv ))
	$(eval VMDNS := $(shell az vm show -d -g myResourceGroup -n vmApp --query fqdns -o tsv ))
	$(eval VMCONNECT := $(shell [ -z "$(VMDNS)" ] && echo $(VMIP) || echo $(VMDNS) ))
	@echo "******************************************************************************************"
	@echo "* IP of the VM is $(VMIP)                                       *"
	@echo "* You can test via url: curl http://$(VMCONNECT)/test                                   *"
	@echo "* You can ssh connect with: ssh -i ~/.ssh/cloud/ssh-key-for-cloud.key -o StrictHostKeyChecking=false app@$(VMCONNECT) *"
	@echo "* You can connect to MandelbrotInTheCloud via: http://$(VMCONNECT) *"
	@echo "******************************************************************************************"
