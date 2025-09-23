Param(
  [Parameter(Mandatory=$true)] [string]$SubscriptionId,
  [Parameter(Mandatory=$true)] [string]$ResourceGroupName = "rg-tfstates",
  [Parameter(Mandatory=$true)] [string]$StorageAccountName,
  [Parameter(Mandatory=$false)] [string]$Location = "eastus"
)

az account set --subscription $SubscriptionId

az group create -n $ResourceGroupName -l $Location | Out-Null

az storage account create `
  -n $StorageAccountName `
  -g $ResourceGroupName `
  -l $Location `
  --sku Standard_LRS | Out-Null

$conn = az storage account show-connection-string -g $ResourceGroupName -n $StorageAccountName -o tsv

az storage container create `
  --name tfstate `
  --connection-string $conn | Out-Null

Write-Host "Terraform backend ready: rg=$ResourceGroupName sa=$StorageAccountName container=tfstate"

