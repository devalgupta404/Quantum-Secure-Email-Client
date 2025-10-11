# Use Python 3.11 slim image
FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY docker/key-manager/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application files
COPY Key_Manager/ .

# Copy startup script
COPY docker/key-manager/start_server.py .

# Create a non-root user
RUN adduser --disabled-password --gecos '' appuser && chown -R appuser /app
USER appuser

# Expose port
EXPOSE 8080

# Set environment variables
ENV FLASK_APP=start_server.py
ENV FLASK_ENV=production

# Run the application
CMD ["python", "start_server.py"]
