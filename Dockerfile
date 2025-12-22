FROM mcr.microsoft.com/powershell:lts-ubuntu-22.04

# Install system dependencies for System.Drawing (required by iText)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgdiplus \
    libc6-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install SimplySql module
SHELL ["pwsh", "-Command"]
RUN Install-Module -Name SimplySql -Force -Scope AllUsers -Repository PSGallery

# Copy setup script and download iText dependencies
COPY setup-libs.ps1 /app/
RUN ./setup-libs.ps1

# Copy application source and templates
COPY src/ /app/src/
COPY templates/ /app/templates/

# Create output directory
RUN New-Item -Path /app/output -ItemType Directory

# Set entrypoint
CMD ["pwsh", "-File", "/app/src/Process-Invoices.ps1"]