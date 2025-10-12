# DockerHub CI/CD Setup

This repository includes automated CI/CD pipeline for building and pushing Docker images to DockerHub.

## Setup Instructions

### 1. GitHub Secrets Configuration

Add the following secrets to your GitHub repository:

1. Go to your repository settings
2. Navigate to "Secrets and variables" → "Actions"
3. Add the following repository secrets:

- `DOCKERHUB_USERNAME`: Your DockerHub username
- `DOCKERHUB_TOKEN`: Your DockerHub access token

### 2. Creating DockerHub Access Token

1. Log in to [DockerHub](https://hub.docker.com/)
2. Go to Account Settings → Security
3. Click "New Access Token"
4. Give it a name (e.g., "GitHub Actions")
5. Copy the token and add it as `DOCKERHUB_TOKEN` secret

### 3. Docker Images

The CI/CD pipeline builds and pushes the following Docker images:

| Service | Image Name | Dockerfile Location |
|---------|------------|-------------------|
| Database | `quantum-secure-database` | `docker/database/Dockerfile` |
| Key Manager | `quantum-secure-key-manager` | `docker/key-manager/Dockerfile` |
| OTP Server | `quantum-secure-otp-server` | `docker/otp-server/Dockerfile` |
| AES Server | `quantum-secure-aes-server` | `docker/aes-server/Dockerfile` |
| Auth Service | `quantum-secure-auth-service` | `docker/auth/Dockerfile` |
| Backend | `quantum-secure-backend` | `docker/backend/Dockerfile` |
| Quantum Server | `quantum-secure-server` | `quantum-secure-email-client/quant-sec-server/Dockerfile` |

## Workflow Triggers

The CI/CD pipeline runs on:

- **Push to main/develop branches**: Builds and pushes images with `latest` and commit SHA tags
- **Pull requests**: Builds images locally for testing (no push to DockerHub)
- **Releases**: Builds and pushes images with version tags

## Parallel Execution

The workflow uses GitHub Actions matrix strategy to build all Docker images **in parallel**, significantly reducing build time:

- Each service builds in its own parallel job
- All 7 images build simultaneously instead of sequentially
- Faster CI/CD pipeline execution

## Using DockerHub Images

### Option 1: Using Docker Compose Override

Use the provided override file to run with DockerHub images:

```bash
# Set your DockerHub username
export DOCKERHUB_USERNAME=your-username

# Run with DockerHub images
docker-compose -f docker/docker-compose.yml -f docker/docker-compose.dockerhub.yml up
```

### Option 2: Manual Docker Commands

```bash
# Pull and run individual services
docker pull your-username/quantum-secure-database:latest
docker pull your-username/quantum-secure-key-manager:latest
docker pull your-username/quantum-secure-otp-server:latest
docker pull your-username/quantum-secure-aes-server:latest
docker pull your-username/quantum-secure-auth-service:latest
docker pull your-username/quantum-secure-backend:latest
docker pull your-username/quantum-secure-server:latest
```

## Image Tags

- `latest`: Latest build from main branch
- `{commit-sha}`: Specific commit SHA
- `pr-{number}`: Pull request builds (not pushed to DockerHub)
- `{version}`: Release version tags

## Troubleshooting

### Common Issues

1. **Authentication Failed**: Ensure `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` secrets are correctly set
2. **Build Failures**: Check Dockerfile paths and context in the workflow
3. **Push Failures**: Verify DockerHub permissions and token validity

### Checking Workflow Status

1. Go to your repository on GitHub
2. Click on "Actions" tab
3. View the "Build and Push Docker Images to DockerHub" workflow runs

### Local Testing

You can test the Docker builds locally:

```bash
# Test database build
docker build -f docker/database/Dockerfile -t test-database .

# Test key manager build
docker build -f docker/key-manager/Dockerfile -t test-key-manager .

# Test other services similarly...
```

## Environment Variables

The following environment variables are used in the workflow:

- `DOCKERHUB_USERNAME`: Your DockerHub username (from GitHub secrets)
- `DOCKERHUB_TOKEN`: Your DockerHub access token (from GitHub secrets)

## Security Notes

- Never commit DockerHub credentials to the repository
- Use GitHub secrets for sensitive information
- Regularly rotate DockerHub access tokens
- Consider using DockerHub organization accounts for team projects
