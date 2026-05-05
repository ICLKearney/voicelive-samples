<#
.SYNOPSIS
    Build container image via ACR cloud build and update the Container App.
    Works without local Docker — uses 'az acr build' for remote builds.
#>
param()

$ErrorActionPreference = "Stop"

# Prevent Azure CLI (colorama) from crashing on Unicode output (e.g., vite's ✓)
$env:PYTHONUTF8 = "1"

function Get-AzdEnvValue {
    param([Parameter(Mandatory = $true)][string]$Key)

    $value = azd env get-value $Key 2>$null
    if ($LASTEXITCODE -ne 0) {
        return $null
    }

    if ($null -eq $value) {
        return $null
    }

    $trimmed = ($value | Out-String).Trim()
    if (-not $trimmed) {
        return $null
    }

    return $trimmed
}

# Read azd env values
$acrName = Get-AzdEnvValue -Key "AZURE_CONTAINER_REGISTRY_NAME"
$envName = Get-AzdEnvValue -Key "AZURE_ENV_NAME"
$rgName = Get-AzdEnvValue -Key "AZURE_RESOURCE_GROUP_NAME"
$appName = Get-AzdEnvValue -Key "AZURE_CONTAINER_APP_NAME"

# Determine backend language and corresponding Dockerfile
$backendLang = Get-AzdEnvValue -Key "BACKEND_LANGUAGE"
if (-not $backendLang) { $backendLang = "python" }
if ($backendLang -notin @("python", "javascript", "java", "csharp")) {
    Write-Host "Unknown BACKEND_LANGUAGE '$backendLang', defaulting to 'python'."
    $backendLang = "python"
}
$dockerfile = "Dockerfile.$backendLang"

if (-not $acrName) {
    Write-Host "ACR not provisioned yet — run 'azd provision' first."
    exit 1
}

$loginServer = (az acr show --name $acrName --query loginServer --output tsv 2>$null)
$timestamp = Get-Date -Format "yyyyMMddHHmmss"
$imageTag = "$loginServer/voicelive-web:${envName}-${timestamp}"

Write-Host "===== Building Container Image ====="
Write-Host "  ACR:        $acrName"
Write-Host "  Image:      $imageTag"
Write-Host "  Dockerfile: $dockerfile"
Write-Host ""

# Try local Docker first, fall back to ACR cloud build
$dockerAvailable = $null -ne (Get-Command docker -ErrorAction SilentlyContinue)
$dockerRunning = $false
if ($dockerAvailable) {
    docker info *>$null
    $dockerRunning = ($LASTEXITCODE -eq 0)
}

if ($dockerRunning) {
    Write-Host "Using local Docker build..."
    docker build -t $imageTag -f $dockerfile .
    if ($LASTEXITCODE -ne 0) { throw "Docker build failed" }

    Write-Host "Pushing to ACR..."
    az acr login --name $acrName
    docker push $imageTag
    if ($LASTEXITCODE -ne 0) { throw "Docker push failed" }
} else {
    Write-Host "Using ACR cloud build (no local Docker required)..."
    # --no-logs: skip real-time log streaming to avoid Azure CLI colorama
    # crash on Unicode output (vite's ✓) on Windows (cp1252).
    az acr build --registry $acrName --image "voicelive-web:${envName}-${timestamp}" --file $dockerfile . --no-logs 2>&1
    if ($LASTEXITCODE -ne 0) { throw "ACR cloud build failed" }
}

# Update Container App with the new image
Write-Host ""
Write-Host "===== Updating Container App ====="
Write-Host "  App:   $appName"
Write-Host "  Image: $imageTag"

az containerapp update `
    --name $appName `
    --resource-group $rgName `
    --image $imageTag 2>&1
if ($LASTEXITCODE -ne 0) { throw "Container App update failed" }

Write-Host ""
Write-Host "===== Deploy Complete ====="
$fqdn = az containerapp show --name $appName --resource-group $rgName --query "properties.configuration.ingress.fqdn" --output tsv 2>$null
Write-Host "  URL: https://$fqdn"
