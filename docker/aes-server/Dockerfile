# Use Python 3.11 slim image
FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    build-essential \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy C source files and compile AES GCM demo
COPY level2new/aes_gcm.c level2new/aes_gcm.h level2new/aes.c level2new/aes.h level2new/main_gcm.c ./
RUN gcc -o aes_gcm_demo aes_gcm.c aes.c main_gcm.c -lcrypto

# Copy requirements and install Python dependencies
COPY docker/aes-server/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application files
COPY level2new/ .

# Create a non-root user
RUN adduser --disabled-password --gecos '' appuser && chown -R appuser /app
USER appuser

# Expose port
EXPOSE 8081

# Set environment variables
ENV FLASK_APP=server.py
ENV FLASK_ENV=production

# Run the application
CMD ["python", "server.py"]
