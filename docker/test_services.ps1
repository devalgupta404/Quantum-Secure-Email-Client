Write-Host "Testing all Quantum Secure Email Client services..."

# Test backend API
Write-Host "Testing Backend API (port 5001)..."
try {
    $response = Invoke-WebRequest -Uri http://localhost:5001/api/health -UseBasicParsing
    Write-Host "✓ Backend API: $($response.StatusCode)"
} catch {
    Write-Host "✗ Backend API failed: $($_.Exception.Message)"
}

# Test frontend
Write-Host "Testing Frontend (port 80)..."
try {
    $response = Invoke-WebRequest -Uri http://localhost/ -UseBasicParsing
    Write-Host "✓ Frontend: $($response.StatusCode)"
} catch {
    Write-Host "✗ Frontend failed: $($_.Exception.Message)"
}

# Test services from within Docker network
Write-Host "Testing Auth Service from Docker network..."
try {
    $result = docker exec quantum_backend curl -f http://auth-service:2023/health 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ Auth Service: OK"
    } else {
        Write-Host "✗ Auth Service failed"
    }
} catch {
    Write-Host "✗ Auth Service test failed: $($_.Exception.Message)"
}

Write-Host "Testing Key Manager from Docker network..."
try {
    $result = docker exec quantum_backend curl -f http://key-manager:2020/health 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ Key Manager: OK"
    } else {
        Write-Host "✗ Key Manager failed"
    }
} catch {
    Write-Host "✗ Key Manager test failed: $($_.Exception.Message)"
}

Write-Host "Testing AES Server from Docker network..."
try {
    $result = docker exec quantum_backend curl -f http://aes-server:2021/health 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ AES Server: OK"
    } else {
        Write-Host "✗ AES Server failed"
    }
} catch {
    Write-Host "✗ AES Server test failed: $($_.Exception.Message)"
}

Write-Host "Testing PostgreSQL connection..."
try {
    $result = docker exec quantum_postgres pg_isready -U postgres -d quantum_auth 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ PostgreSQL: OK"
    } else {
        Write-Host "✗ PostgreSQL failed"
    }
} catch {
    Write-Host "✗ PostgreSQL test failed: $($_.Exception.Message)"
}

Write-Host "All service tests completed!"
