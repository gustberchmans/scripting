# STAGE 1: Builder - Download modules
FROM mcr.microsoft.com/powershell:latest as builder

# Set a directory for the downloaded modules
WORKDIR /modules

# Install curl and unzip for reliable manual downloads
RUN apt-get update && apt-get install -y curl unzip ca-certificates

# Download PSPDF v1.0.0 directly
RUN curl -L -o PSPDF.zip "https://www.powershellgallery.com/api/v2/package/PSPDF/1.0.0" && \
    unzip -q PSPDF.zip -d PSPDF && \
    rm PSPDF.zip

# Download SimplySql v1.9.1 directly (replacing the broken MySql module)
RUN curl -L -o SimplySql.zip "https://www.powershellgallery.com/api/v2/package/SimplySql/1.9.1" && \
    unzip -q SimplySql.zip -d SimplySql && \
    rm SimplySql.zip

# STAGE 2: Final Image
FROM mcr.microsoft.com/powershell:latest

# Set the working directory inside the container
WORKDIR /app

# Install system dependencies (wkhtmltopdf is required for PSPDF)
RUN apt-get update && apt-get install -y wkhtmltopdf ca-certificates && rm -rf /var/lib/apt/lists/*


# Copy the pre-downloaded modules from the builder stage into the system-wide module path
COPY --from=builder /modules/PSPDF /usr/local/share/powershell/Modules/PSPDF
COPY --from=builder /modules/SimplySql /usr/local/share/powershell/Modules/SimplySql

# Ensure modules are readable and executable
RUN chmod -R 755 /usr/local/share/powershell/Modules/

# Note: The main script and other directories (templates, output, etc.) 
# will be mounted as volumes via docker-compose, so they don't need to be copied here.
# However, we copy the src directory to ensure the container has the script if not mounted.
COPY ./src /app/src

# The command to run when the container starts
CMD ["pwsh", "-File", "/app/src/Process-Invoices.ps1"]
