# PostgreSQL Database with custom configuration
FROM postgres:15-alpine

# Set environment variables
ENV POSTGRES_DB=quantum_auth
ENV POSTGRES_USER=postgres
ENV POSTGRES_PASSWORD=quantum_secure_password_2024

# Copy custom PostgreSQL configuration
COPY docker/database/postgresql.conf /etc/postgresql/postgresql.conf

# Create directory for custom configuration
RUN mkdir -p /etc/postgresql

# Set proper permissions
RUN chown -R postgres:postgres /etc/postgresql

# Expose port
EXPOSE 5432

# Add health check
HEALTHCHECK --interval=10s --timeout=5s --retries=5 \
  CMD pg_isready -U postgres -d quantum_auth

# Use default entrypoint from postgres image
