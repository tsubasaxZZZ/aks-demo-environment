#!/bin/sh
set -eux

if [ $# != 3 ]; then
    echo "Resource Group or Location or AKS version not specified."
    exit 1
fi

rg=$1
location=$2
aksversion=$3

git clone https://github.com/tsubasaxZZZ/aks-demo-environment.git
cd aks-demo-environment

terraform init

terraform apply -target random_string.uniqstr -var resource_group_name="$rg" -var location="$location" -var aks-version="$aksversion" -auto-approve
terraform plan -var resource_group_name="$rg" -var location="$location" -var aks-version="$aksversion" -out plan.tfplan
terraform apply plan.tfplan

az aks get-credentials -g "$rg" -n $(cat aks-name)

kubectl apply -f deployment.yaml