#!/bin/sh
set -eu

if [ $# != 2 ]; then
    echo "Resource Group or Location not specified."
    exit 1
fi

rg=$1
location=$2

git clone https://github.com/tsubasaxZZZ/aks-demo-environment.git
cd aks-demo-environment

terraform init

terraform apply -target random_string.uniqstr -var resource_group_name=$rg -var location=$location -auto-approve
terraform plan -var resource_group_name=$rg -var location=$location -out plan.tfplan
terraform apply plan.tfplan

az aks get-credentials -g $rg -n $(cat aks-name)

kubectl apply -f deployment.yaml