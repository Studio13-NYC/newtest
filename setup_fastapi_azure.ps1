# Comprehensive setup script for FastAPI on Azure
# Handles:
# 1. GitHub repository setup
# 2. FastAPI application creation
# 3. Azure deployment configuration
# 4. Deployment and push

# Required parameters
param(
    [string]$GitHubUsername = "Studio13-NYC",
    [string]$AzureAppName = "test-data-api"
)

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
    
    # Check if .git already exists
    if (Test-Path ".git") {
        Write-Host "Git repository already initialized."
        # Ensure we're on main branch even for existing repos
        git branch -M main
        return
    }

    # Initialize git
    git init

    # Create GitHub repository if it doesn't exist
    $repoUrl = "https://github.com/$GitHubUsername/$RepoName.git"
    $repoExists = git ls-remote $repoUrl 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Creating new GitHub repository: $RepoName"
        gh repo create "$GitHubUsername/$RepoName" --public --confirm
    }
    else {
        Write-Host "Repository already exists on GitHub"
    }

    # Rename the default branch to main
    git branch -M main

    # Add remote (remove duplicate)
    git remote add origin $repoUrl

    # Add error handling
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to configure GitHub repository"
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

# Main execution
$ErrorActionPreference = "Stop"
$currentFolder = Split-Path -Leaf (Get-Location)

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

# Execute setup steps
Check-Prerequisites
Setup-GitHubRepo -RepoName $currentFolder
Create-FastAPIApp
Create-RequirementsFile
Create-AzureConfig
Create-GitignoreFile
Setup-VirtualEnv
Commit-AndPush

Write-Host "`nSetup completed successfully!"
Write-Host "Next steps:"
Write-Host "1. Configure GitHub Actions in the repository"
Write-Host "2. Set up Azure App Service"
Write-Host "3. Add the publish profile to GitHub Secrets"
Write-Host "4. Test the deployment at: https://$AzureAppName.azurewebsites.net" 