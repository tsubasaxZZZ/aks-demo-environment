# Terraform による AKS デモ環境の展開

## 手順

### 1. Terraform 実行環境のセットアップ

以下のツールをインストールした Linux 環境を用意する。

#### Azure CLI

- Install the Azure CLI
    - https://docs.microsoft.com/en-us/cli/azure/install-azure-cli
- Azure CLI のログイン(<font color="red">※展開先のサブスクリプションを間違えないこと</font>)
    - az login
    - az account list
    - az account set --subscription <サブスクリプション>

#### terraform

- Download Terraform
    - https://www.terraform.io/downloads.html

#### kubectl

```
az aks install-cli
```

### 2. Terraform の実行

#### git clone

```
git clone https://github.com/tsubasaxZZZ/aks-demo-environment.git
```

#### Terraform の実行

```
terraform init
terraform plan -var resource_group_name=<リソース グループ名> -var location=<リージョン(AZがあるリージョン)> -out plan.tfplan
例) terraform plan -var resource_group_name=rg-aksdemo2 -var location=southeastasia -out plan.tfplan
terraform apply plan.tfplan
```

### 3. ワークロードのデプロイ

1. deployment.yaml のダウンロード
    - https://github.com/hiroyha1/uploader/blob/master/sample/deployment.yaml
1. 必要なところを書き換え
1. apply
    - `kubectl apply -f deployment.yaml`

### 4. 確認

以下へアクセス。

`http://<Application Gateway の IP アドレス>/uploader/actuator/health`

以下の様なレスポンスが返ってくることを確認。

```
{"status":"UP","components":{"db":{"status":"UP","details":{"database":"Microsoft SQL Server","result":1,"validationQuery":"SELECT 1"}},"diskSpace":{"status":"UP","details":{"total":133018140672,"free":117697044480,"threshold":10485760}},"ping":{"status":"UP"}}}
```