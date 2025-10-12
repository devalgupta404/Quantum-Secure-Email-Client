# Use Python 3.11 slim image
FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY docker/otp-server/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application files
COPY level2new/otp_server.py .

# Create a non-root user
RUN adduser --disabled-password --gecos '' appuser && chown -R appuser /app
USER appuser

# Expose port
EXPOSE 2021

# Set environment variables
ENV FLASK_APP=otp_server.py
ENV FLASK_ENV=production

# Run the application
CMD ["python", "otp_server.py"]
