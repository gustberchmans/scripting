<#
.SYNOPSIS
  Generates an HTML report of the invoice processing status.
  Fulfills the "Visual Interface/Reporting" extra requirement.
#>

# Import Custom Module
Import-Module "$PSScriptRoot/PeppolProcessor.psm1" -Force

New-PeppolReport