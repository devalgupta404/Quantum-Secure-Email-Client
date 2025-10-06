# PowerShell script to set up environment variables
# Run this script to set up your development environment

Write-Host "🚀 Setting up QuMail Authentication Environment..." -ForegroundColor Green

# Check if .env file exists
if (-not (Test-Path ".env")) {
    Write-Host "❌ .env file not found!" -ForegroundColor Red
    Write-Host "Please copy .env.example to .env and update with your values:" -ForegroundColor Yellow
    Write-Host "cp .env.example .env" -ForegroundColor Cyan
    exit 1
}

Write-Host "✅ .env file found" -ForegroundColor Green

# Load environment variables
Write-Host "📋 Loading environment variables..." -ForegroundColor Blue
Get-Content .env | ForEach-Object {
    if ($_ -match "^([^#][^=]+)=(.*)$") {
        $name = $matches[1].Trim()
        $value = $matches[2].Trim()
        [Environment]::SetEnvironmentVariable($name, $value, "Process")
        Write-Host "  ✓ $name" -ForegroundColor Gray
    }
}

Write-Host "🔧 Installing dependencies..." -ForegroundColor Blue
dotnet restore

Write-Host "🏗️ Building project..." -ForegroundColor Blue
dotnet build

Write-Host "✅ Setup complete! You can now run 'dotnet run' to start the server" -ForegroundColor Green
Write-Host "📚 API Documentation will be available at: http://localhost:5000/swagger" -ForegroundColor Cyan
