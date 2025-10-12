# Port Analysis for Quantum Secure Email Client

## Server Port Status Analysis

### Currently Used Ports on Server:
- **4666** - llvm-obfuscator-frontend
- **6379** - Redis (infisical-dev-redis)
- **5432** - PostgreSQL (infisical-db) ⚠️ **CONFLICT RESOLVED**
- **3000** - Grafana (monitoring)
- **9090** - Prometheus (monitoring)
- **8081** - cAdvisor (monitoring)
- **9115** - Blackbox Exporter (monitoring)
- **9091** - Pushgateway (monitoring)
- **9100** - Node Exporter (monitoring)
- **8080** - Ghost

### Quantum Secure Email Client Ports:

| Service | Internal Port | External Port | Status |
|---------|---------------|----------------|--------|
| PostgreSQL | 5432 | **5433** | ✅ **CHANGED** (was 5432) |
| Key Manager | 2020 | - | ✅ Available |
| OTP Server | 2021 | - | ✅ Available |
| AES Server | 2022 | - | ✅ Available |
| Auth Service | 2023 | - | ✅ Available |
| Backend API | 5001 | **5001** | ✅ Available |

## Changes Made:

### 1. PostgreSQL Port Conflict Resolution
- **Problem**: Server already has PostgreSQL on port 5432
- **Solution**: Changed external port mapping to 5433
- **Internal**: Services still connect to PostgreSQL on port 5432 internally
- **External**: Access PostgreSQL via `localhost:5433`

### 2. Port Mapping Summary
```yaml
# External access ports
5433 -> PostgreSQL (was 5432)
5001 -> Backend API

# Internal service ports (no external access needed)
2020 -> Key Manager
2021 -> OTP Server  
2022 -> AES Server
2023 -> Auth Service
```

## Deployment Commands:

```bash
# Navigate to docker directory
cd docker

# Start all services
docker-compose up -d

# Check running containers
docker ps

# View logs
docker-compose logs -f

# Stop services
docker-compose down
```

## Service Dependencies:
1. **PostgreSQL** (5433) - Database
2. **Key Manager** (2020) - Key management service
3. **OTP Server** (2021) - Depends on Key Manager
4. **AES Server** (2022) - Depends on Key Manager
5. **Auth Service** (2023) - Depends on PostgreSQL
6. **Backend API** (5001) - Depends on all services

## Health Checks:
- PostgreSQL: `pg_isready` on port 5432
- Auth Service: HTTP health check on port 2023
- Backend: Health check available (currently commented out)

## Network Configuration:
- All services use `quantum_network` bridge network
- Internal communication uses service names
- External access only for PostgreSQL (5433) and Backend (5001)
