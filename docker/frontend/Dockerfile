# Use the official Flutter image
FROM ghcr.io/cirruslabs/flutter:stable AS build

# Set working directory
WORKDIR /app

# Copy pubspec files
COPY frontend/pubspec.yaml frontend/pubspec.lock ./

# Get dependencies
RUN flutter pub get

# Copy source code
COPY frontend/ .

# Build the Flutter web app
RUN flutter build web --release

# Use nginx to serve the built app
FROM nginx:alpine

# Copy the built app to nginx html directory
COPY --from=build /app/build/web /usr/share/nginx/html

# Copy nginx configuration
COPY docker/frontend/nginx.conf /etc/nginx/conf.d/default.conf

# Expose port 80
EXPOSE 80

# Start nginx
CMD ["nginx", "-g", "daemon off;"]
