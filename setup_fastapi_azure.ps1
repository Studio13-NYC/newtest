# Comprehensive setup script for FastAPI on Azure
# Handles:
# 1. GitHub repository setup
# 2. FastAPI application creation
# 3. Azure deployment configuration
# 4. Deployment and push

# Required parameters
param(
    [string]$GitHubUsername = "Studio13-NYC"
)

function Get-UserParameters {
    Write-Host "`nPlease provide Azure configuration details:"
    Write-Host "----------------------------------------"
    
    $script:ResourceGroup = Read-Host "Resource Group name (default: myResourceGroup)"
    if ([string]::IsNullOrWhiteSpace($script:ResourceGroup)) {
        $script:ResourceGroup = "myResourceGroup"
    }
    
    $script:Location = Read-Host "Azure Region (default: eastus)"
    if ([string]::IsNullOrWhiteSpace($script:Location)) {
        $script:Location = "eastus"
    }
    
    $script:AppServicePlan = Read-Host "App Service Plan name (default: myAppServicePlan)"
    if ([string]::IsNullOrWhiteSpace($script:AppServicePlan)) {
        $script:AppServicePlan = "myAppServicePlan"
    }
    
    $script:AzureAppName = Read-Host "Web App name (must be globally unique)"
    while ([string]::IsNullOrWhiteSpace($script:AzureAppName)) {
        Write-Host "Web App name is required and must be globally unique"
        $script:AzureAppName = Read-Host "Web App name"
    }

    # Confirm parameters
    Write-Host "`nConfirm Azure configuration:"
    Write-Host "Resource Group: $script:ResourceGroup"
    Write-Host "Location: $script:Location"
    Write-Host "App Service Plan: $script:AppServicePlan"
    Write-Host "Web App Name: $script:AzureAppName"
    
    $confirm = Read-Host "`nProceed with these settings? (Y/N)"
    if ($confirm -ne "Y") {
        exit 0
    }
}

function Check-Prerequisites {
    Write-Host "Checking prerequisites..."
    
    # Check Git
    try {
        $null = git --version
    }
    catch {
        Write-Error "Git is not installed. Please install Git first."
        exit 1
    }

    # Check Python
    try {
        $pythonVersion = python -c "import sys; print('.'.join(map(str, sys.version_info[:2])))"
        if ([version]$pythonVersion -lt [version]"3.11") {
            Write-Error "Python 3.11 or later is required. Found version $pythonVersion"
            exit 1
        }
    }
    catch {
        Write-Error "Python is not installed or not in PATH"
        exit 1
    }

    # Check Azure CLI
    try {
        $null = az --version
    }
    catch {
        Write-Error "Azure CLI is not installed. Please install it first."
        exit 1
    }
}

function Setup-GitHubRepo {
    param (
        [string]$RepoName
    )
    
    Write-Host "Setting up GitHub repository..."
    
    # Create GitHub repository first
    Write-Host "Creating new GitHub repository: $RepoName"
    gh repo create "$GitHubUsername/$RepoName" --public --confirm
    
    # Then initialize git if needed
    if (-not (Test-Path ".git")) {
        git init
        git branch -M main
    }
    
    # Set the remote
    git remote remove origin 2>$null
    git remote add origin "https://github.com/$GitHubUsername/$RepoName.git"

    # Verify repository was created and remote is set correctly
    try {
        $repoCheck = gh repo view "$GitHubUsername/$RepoName" --json url 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to verify repository creation"
        }
    }
    catch {
        Write-Error "Failed to create or verify GitHub repository: $_"
        exit 1
    }
}

function Create-FastAPIApp {
    Write-Host "Creating FastAPI application structure..."
    
    # Create directory structure
    $directories = @(
        "app",
        "app/api",
        "app/core",
        "app/schemas",
        "app/tests"
    )
    
    foreach ($dir in $directories) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir | Out-Null
        }
    }

    # Create __init__.py files
    foreach ($dir in $directories) {
        $initFile = Join-Path $dir "__init__.py"
        if (-not (Test-Path $initFile)) {
            "" | Out-File -FilePath $initFile -Encoding UTF8
        }
    }

    # Create main.py
    $mainAppContent = @"
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI(
    title="FastAPI Test API",
    description="A test API with health check and documentation",
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
    openapi_url="/openapi.json"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/")
async def root():
    return {
        "message": "Hello World",
        "docs_url": "/docs",
        "health_check": "/health"
    }

@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "version": "1.0.0"
    }
"@ 
    $mainAppContent | Out-File -FilePath "app/main.py" -Encoding UTF8
}

function Create-RequirementsFile {
    Write-Host "Creating requirements.txt..."
    
@"
fastapi>=0.68.0
uvicorn>=0.15.0
gunicorn>=20.1.0
python-multipart>=0.0.5
pydantic>=1.8.0
python-jose[cryptography]>=3.3.0
passlib[bcrypt]>=1.7.4
python-dotenv>=0.19.0
"@ | Out-File -FilePath "requirements.txt" -Encoding UTF8
}

function Create-AzureConfig {
    Write-Host "Creating Azure configuration files..."
    
    # Create startup.sh
@"
#!/bin/bash
set -e

echo "Current directory: \$(pwd)"
echo "Listing directory contents:"
ls -la

if [ ! -d "antenv" ]; then
    echo "Creating virtual environment..."
    python -m venv antenv
fi

echo "Activating virtual environment..."
source antenv/bin/activate

echo "Installing dependencies..."
pip install --upgrade pip
pip install -r requirements.txt

echo "Starting FastAPI application..."
cd /home/site/wwwroot
export PYTHONPATH=/home/site/wwwroot
gunicorn --bind=0.0.0.0:8000 --timeout 600 --workers 4 --access-logfile - --error-logfile - --log-level debug wsgi:application
"@ | Out-File -FilePath "startup.sh" -Encoding UTF8 -NoNewline

    # Create wsgi.py
@"
from app.main import app
application = app
"@ | Out-File -FilePath "wsgi.py" -Encoding UTF8

    # Create web.config
@"
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <system.webServer>
    <handlers>
      <add name="PythonHandler" path="*" verb="*" modules="httpPlatformHandler" resourceType="Unspecified"/>
    </handlers>
    <httpPlatform processPath="%home%\site\wwwroot\antenv\Scripts\python.exe"
                  arguments=".\startup.sh"
                  stdoutLogEnabled="true"
                  stdoutLogFile="%home%\LogFiles\python.log"
                  startupTimeLimit="60">
      <environmentVariables>
        <environmentVariable name="PYTHONPATH" value="."/>
        <environmentVariable name="PORT" value="%HTTP_PLATFORM_PORT%"/>
      </environmentVariables>
    </httpPlatform>
  </system.webServer>
</configuration>
"@ | Out-File -FilePath "web.config" -Encoding UTF8

    # Create .deployment
@"
[config]
SCM_DO_BUILD_DURING_DEPLOYMENT=true
POST_BUILD_COMMAND=python -m pip install --upgrade pip && pip install -r requirements.txt
"@ | Out-File -FilePath ".deployment" -Encoding UTF8
}

function Create-GitignoreFile {
    Write-Host "Creating .gitignore..."
    
@"
# Python
__pycache__/
*.py[cod]
*$py.class
*.so
.Python
build/
develop-eggs/
dist/
downloads/
eggs/
.eggs/
lib/
lib64/
parts/
sdist/
var/
wheels/
*.egg-info/
.installed.cfg
*.egg

# Virtual Environment
.env
.venv
env/
venv/
ENV/
env.bak/
venv.bak/

# VS Code
.vscode/

# Azure
*.PublishSettings

# Logs
*.log
"@ | Out-File -FilePath ".gitignore" -Encoding UTF8
}

function Setup-VirtualEnv {
    Write-Host "Setting up virtual environment..."
    
    if (-not (Test-Path ".venv")) {
        python -m venv .venv
    }
    
    & ".venv\Scripts\Activate.ps1"
    python -m pip install --upgrade pip
    pip install -r requirements.txt
}

function Commit-AndPush {
    Write-Host "Committing and pushing changes..."
    
    git add .
    git commit -m "Initial commit: FastAPI Azure setup"
    
    # Add error handling for push
    $pushResult = git push -u origin main 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to push to GitHub: $pushResult"
        exit 1
    }
}

function Create-GitHubWorkflow {
    Write-Host "Creating GitHub Actions workflow..."
    
    # Create .github/workflows directory if it doesn't exist
    $workflowPath = ".github/workflows"
    if (-not (Test-Path $workflowPath)) {
        New-Item -ItemType Directory -Path $workflowPath -Force | Out-Null
    }

    # Create azure-deploy.yml
    $workflowContent = @"
name: Deploy to Azure
on:
  push:
    branches: [ main ]
  workflow_dispatch:

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v2

    - name: Set up Python
      uses: actions/setup-python@v2
      with:
        python-version: '3.11'

    - name: Install dependencies
      run: |
        python -m pip install --upgrade pip
        pip install -r requirements.txt

    - name: Deploy to Azure Web App
      uses: azure/webapps-deploy@v2
      with:
        app-name: '$AzureAppName'
        publish-profile: `${{ secrets.AZURE_WEBAPP_PUBLISH_PROFILE }}
"@
    
    $workflowContent | Out-File -FilePath "$workflowPath/azure-deploy.yml" -Encoding UTF8
}

function Setup-AzureResources {
    param (
        [string]$ResourceGroup = "myResourceGroup",
        [string]$Location = "eastus",
        [string]$AppServicePlan = "myAppServicePlan"
    )
    
    Write-Host "Setting up Azure resources..."
    
    try {
        # Check if logged in to Azure
        $account = az account show | ConvertFrom-Json
        Write-Host "Using Azure account: $($account.name)"
    }
    catch {
        Write-Host "Please login to Azure..."
        if ((az login) -eq $null) {
            Write-Error "Azure login failed"
            exit 1
        }
    }
    
    # Create resource group with error handling
    try {
        Write-Host "Creating resource group: $ResourceGroup"
        $rgResult = az group create --name $ResourceGroup --location $Location
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create resource group"
        }
    }
    catch {
        Write-Error "Failed to create Azure Resource Group: $_"
        Cleanup-Resources -ResourceGroup $ResourceGroup -RepoName $currentFolder
        exit 1
    }
    
    # Create App Service plan with error handling
    try {
        Write-Host "Creating App Service plan: $AppServicePlan"
        $planResult = az appservice plan create --name $AppServicePlan --resource-group $ResourceGroup --sku B1 --is-linux
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create App Service Plan"
        }
    }
    catch {
        Write-Error "Failed to create App Service Plan: $_"
        Cleanup-Resources -ResourceGroup $ResourceGroup -RepoName $currentFolder
        exit 1
    }
    
    # Create web app with error handling and validation
    try {
        Write-Host "Creating web app: $AzureAppName"
        $webappResult = az webapp create --name $AzureAppName --resource-group $ResourceGroup --plan $AppServicePlan --runtime "PYTHON:3.11"
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create Web App"
        }
        
        # Verify webapp creation
        $webapp = az webapp show --name $AzureAppName --resource-group $ResourceGroup
        if ($null -eq $webapp) {
            throw "Web App creation verification failed"
        }
    }
    catch {
        Write-Error "Failed to create or verify Web App: $_"
        Cleanup-Resources -ResourceGroup $ResourceGroup -RepoName $currentFolder
        exit 1
    }
}

function Setup-GitHubSecrets {
    param (
        [string]$ResourceGroup = "myResourceGroup"
    )
    
    Write-Host "Setting up GitHub Secrets..."
    
    # Wait for webapp to be ready
    Write-Host "Waiting for web app to be ready..."
    Start-Sleep -Seconds 30
    
    # Get publish profile with retry
    $maxRetries = 3
    $retryCount = 0
    $success = $false
    
    while (-not $success -and $retryCount -lt $maxRetries) {
        try {
            $publishProfile = az webapp deployment list-publishing-profiles `
                --name $AzureAppName `
                --resource-group $ResourceGroup `
                --xml
            $success = $true
        }
        catch {
            $retryCount++
            if ($retryCount -lt $maxRetries) {
                Write-Host "Retrying to get publish profile... Attempt $retryCount of $maxRetries"
                Start-Sleep -Seconds 10
            }
        }
    }
    
    if (-not $success) {
        Write-Error "Failed to get publish profile after $maxRetries attempts"
        exit 1
    }
    
    # Set GitHub secret
    Write-Host "Adding publish profile to GitHub Secrets..."
    $publishProfile | gh secret set AZURE_WEBAPP_PUBLISH_PROFILE
}

function Verify-GitHubAuth {
    Write-Host "Verifying GitHub CLI authentication..."
    try {
        $auth = gh auth status 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Please login to GitHub CLI..."
            gh auth login
        }
    }
    catch {
        Write-Error "GitHub CLI not installed or not accessible"
        exit 1
    }
}

function Cleanup-Resources {
    param (
        [string]$ResourceGroup,
        [string]$RepoName
    )
    
    Write-Host "`nCleaning up resources due to error..."
    
    # Delete Azure resources
    try {
        Write-Host "Removing Azure Resource Group: $ResourceGroup"
        az group delete --name $ResourceGroup --yes --no-wait
    }
    catch {
        Write-Warning "Failed to delete Azure Resource Group: $_"
    }
    
    # Delete GitHub repository
    try {
        Write-Host "Removing GitHub repository: $RepoName"
        gh repo delete "$GitHubUsername/$RepoName" --yes
    }
    catch {
        Write-Warning "Failed to delete GitHub repository: $_"
    }
    
    # Remove local git repository
    try {
        Write-Host "Cleaning up local git repository..."
        Remove-Item -Path ".git" -Recurse -Force -ErrorAction SilentlyContinue
    }
    catch {
        Write-Warning "Failed to clean up local git repository: $_"
    }
}

# Main execution
$ErrorActionPreference = "Stop"
$currentFolder = Split-Path -Leaf (Get-Location)

# Add verification steps at the start
Verify-GitHubAuth

try {
    Write-Host "Starting comprehensive setup for: $currentFolder"
    Write-Host "This script will:"
    Write-Host "1. Check prerequisites"
    Write-Host "2. Setup GitHub repository"
    Write-Host "3. Create FastAPI application"
    Write-Host "4. Configure Azure deployment"
    Write-Host "5. Push to GitHub"

    $continue = Read-Host "Continue? (Y/N)"
    if ($continue -ne "Y") {
        exit 0
    }

    # Get Azure parameters first
    Get-UserParameters

    # Execute setup steps with error handling
    Check-Prerequisites
    Setup-GitHubRepo -RepoName $currentFolder
    Create-FastAPIApp
    Create-RequirementsFile
    Create-AzureConfig
    Create-GitignoreFile
    Setup-VirtualEnv
    Create-GitHubWorkflow
    Setup-AzureResources -ResourceGroup $script:ResourceGroup -Location $script:Location -AppServicePlan $script:AppServicePlan
    Setup-GitHubSecrets -ResourceGroup $script:ResourceGroup
    Commit-AndPush

    Write-Host "`nSetup completed successfully!"
    Write-Host "Your application will be available at: https://$AzureAppName.azurewebsites.net"
}
catch {
    Write-Error "Setup failed: $_"
    Cleanup-Resources -ResourceGroup $script:ResourceGroup -RepoName $currentFolder
    exit 1
} 