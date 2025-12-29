<#
.SYNOPSIS
  Entry point for the Peppol Invoice Processor.
  All logic is contained within the PeppolProcessor module.
#>

# Import Custom Module
Import-Module "$PSScriptRoot/PeppolProcessor.psm1" -Force

# Start the processor
# It will automatically pick up DB_HOST etc from environment variables
# because we defined them as default values in the function parameters.
Start-PeppolProcessor
