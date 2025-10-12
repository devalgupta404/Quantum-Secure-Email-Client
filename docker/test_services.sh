#!/bin/bash

echo "Testing all Quantum Secure Email Client services..."

# Test backend API
echo "Testing Backend API (port 5001)..."
curl -f http://localhost:5001/api/health || echo "Backend API failed"

# Test frontend
echo "Testing Frontend (port 80)..."
curl -f http://localhost/ || echo "Frontend failed"

# Test services from within Docker network
echo "Testing Auth Service from Docker network..."
docker exec quantum_backend curl -f http://auth-service:2023/health || echo "Auth service failed"

echo "Testing Key Manager from Docker network..."
docker exec quantum_backend curl -f http://key-manager:2020/health || echo "Key Manager failed"

echo "Testing AES Server from Docker network..."
docker exec quantum_backend curl -f http://aes-server:2021/health || echo "AES Server failed"

echo "Testing PostgreSQL connection..."
docker exec quantum_postgres pg_isready -U postgres -d quantum_auth || echo "PostgreSQL failed"

echo "All service tests completed!"
