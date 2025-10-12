# Authentication Service for Quantum Secure Email Client
FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
  gcc \
  libpq-dev \
  curl \
  && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY docker/auth/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application files
COPY auth/ .

# Create a non-root user
RUN adduser --disabled-password --gecos '' appuser && chown -R appuser /app
USER appuser

# Expose port
EXPOSE 2023

# Set environment variables
ENV FLASK_APP=auth_server.py
ENV FLASK_ENV=production
ENV PYTHONPATH=/app

# Health check
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
  CMD curl -f http://localhost:2023/health || exit 1

# Run the application
CMD ["python", "auth_server.py"]
