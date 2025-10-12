#!/bin/bash

# Test script to verify Docker builds work locally
# This script builds all Docker images locally without pushing

set -e

echo "🧪 Testing Docker builds locally..."
echo "=================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to test Docker build
test_build() {
    local service_name=$1
    local dockerfile_path=$2
    local context_path=$3
    
    echo -e "${YELLOW}Testing $service_name...${NC}"
    
    if docker build -f "$dockerfile_path" -t "test-$service_name" "$context_path" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ $service_name build successful${NC}"
        return 0
    else
        echo -e "${RED}❌ $service_name build failed${NC}"
        return 1
    fi
}

# Track build results
failed_builds=()
successful_builds=()

echo "Building Docker images..."

# Test each service
if test_build "database" "docker/database/Dockerfile" "."; then
    successful_builds+=("database")
else
    failed_builds+=("database")
fi

if test_build "key-manager" "docker/key-manager/Dockerfile" "."; then
    successful_builds+=("key-manager")
else
    failed_builds+=("key-manager")
fi

if test_build "otp-server" "docker/otp-server/Dockerfile" "."; then
    successful_builds+=("otp-server")
else
    failed_builds+=("otp-server")
fi

if test_build "aes-server" "docker/aes-server/Dockerfile" "."; then
    successful_builds+=("aes-server")
else
    failed_builds+=("aes-server")
fi

if test_build "auth-service" "docker/auth/Dockerfile" "."; then
    successful_builds+=("auth-service")
else
    failed_builds+=("auth-service")
fi

if test_build "backend" "docker/backend/Dockerfile" "."; then
    successful_builds+=("backend")
else
    failed_builds+=("backend")
fi


if test_build "quantum-server" "quantum-secure-email-client/quant-sec-server/Dockerfile" "quantum-secure-email-client"; then
    successful_builds+=("quantum-server")
else
    failed_builds+=("quantum-server")
fi

echo ""
echo "=================================="
echo "📊 Build Results Summary"
echo "=================================="

if [ ${#successful_builds[@]} -gt 0 ]; then
    echo -e "${GREEN}✅ Successful builds (${#successful_builds[@]}):${NC}"
    for build in "${successful_builds[@]}"; do
        echo "  - $build"
    done
fi

if [ ${#failed_builds[@]} -gt 0 ]; then
    echo -e "${RED}❌ Failed builds (${#failed_builds[@]}):${NC}"
    for build in "${failed_builds[@]}"; do
        echo "  - $build"
    done
fi

echo ""
if [ ${#failed_builds[@]} -eq 0 ]; then
    echo -e "${GREEN}🎉 All Docker builds successful! CI/CD pipeline should work correctly.${NC}"
    exit 0
else
    echo -e "${RED}⚠️  Some builds failed. Please check the Dockerfiles and dependencies.${NC}"
    exit 1
fi
