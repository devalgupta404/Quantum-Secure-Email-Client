# Use the official .NET 9 runtime as base image
FROM mcr.microsoft.com/dotnet/aspnet:9.0 AS base
WORKDIR /app
EXPOSE 5001

# Use the SDK image to build the application
FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src

# Copy project files
COPY ["Email_client/QuMail.EmailProtocol/QuMail.EmailProtocol.csproj", "."]
RUN dotnet restore "QuMail.EmailProtocol.csproj"

# Copy the rest of the source code
COPY Email_client/QuMail.EmailProtocol/ .

# Build the application
RUN dotnet build "QuMail.EmailProtocol.csproj" -c Release -o /app/build

# Publish the application
FROM build AS publish
RUN dotnet publish "QuMail.EmailProtocol.csproj" -c Release -o /app/publish

# Create the final runtime image
FROM base AS final
WORKDIR /app

# Copy the published application
COPY --from=publish /app/publish .

# Copy the level1.dll file
COPY Email_client/QuMail.EmailProtocol/level1.dll .

# Set environment variables
ENV ASPNETCORE_URLS=http://+:5001
ENV ASPNETCORE_ENVIRONMENT=Production

# Create a non-root user
RUN adduser --disabled-password --gecos '' appuser && chown -R appuser /app
USER appuser

ENTRYPOINT ["dotnet", "QuMail.EmailProtocol.dll"]
