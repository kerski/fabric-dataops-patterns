# Automated Job for the Dqv Testing Pattern

$secret = ${env:PASSWORD_OR_CLIENTSECRET} | ConvertTo-SecureString -AsPlainText -Force
$credentials = [System.Management.Automation.PSCredential]::new(${env:USERNAME_OR_CLIENTID}, $secret)                  

# Check if specific datasets need to be tested
$lengthCheck = "${env:DATASET_IDS}".Trim()
if ($lengthCheck -gt 0) {
    $datasetsToTest = "${env:DATASET_IDS}".Trim() -split ','
}
else {
    $datasetsToTest = @()
}

# Run tests
Invoke-DQVTesting -WorkspaceName "${env:WORKSPACE_NAME}" `
    -Credential $credentials `
    -TenantId "${env:TENANT_ID}" `
    -DatasetId $datasetsToTest `
    -LogOutput "ADO"