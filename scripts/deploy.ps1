Param(
  [Parameter(Mandatory=$true)] [string]$SubscriptionId,
  [Parameter(Mandatory=$true)] [string]$TenantId,
  [Parameter(Mandatory=$true)] [string]$ClientId,
  [Parameter(Mandatory=$true)] [string]$Location,
  [Parameter(Mandatory=$true)] [string]$Environment,
  [Parameter(Mandatory=$true)] [string]$JwtSecret
)

Push-Location "$PSScriptRoot\..\infra"

$backendPath = Join-Path (Get-Location) 'backend.tf'
if (!(Test-Path $backendPath)) {
  Write-Host "backend.tf not found. Copy infra/backend.tf.example to infra/backend.tf and edit values."
  Pop-Location
  exit 1
}

$env:ARM_TENANT_ID = $TenantId
$env:ARM_SUBSCRIPTION_ID = $SubscriptionId
$env:ARM_CLIENT_ID = $ClientId

terraform init

terraform apply -auto-approve `
  -var "location=$Location" `
  -var "environment=$Environment" `
  -var "jwt_secret=$JwtSecret"

Pop-Location

