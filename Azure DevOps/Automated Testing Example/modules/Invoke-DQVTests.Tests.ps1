Describe 'Invoke-DQVTests' {
    BeforeAll { 
        Import-Module .\Invoke-DQVTests.psm1 -Force

        # Retrieve specific variables from json so we don't keep sensitive values in 
        # source control
        $variables = Get-Content .\Invoke-DQVTests.config.json | ConvertFrom-Json        
        $secret = $variables.TestPassword | ConvertTo-SecureString -AsPlainText -Force
        $credentials = [System.Management.Automation.PSCredential]::new($variables.TestUserName,$secret)        

    }

    # Clean up
    AfterAll {
    }

    # Check if File Exists
    It 'Module should exist' {
        $isInstalled = Get-Command Invoke-DQVTests
        $isInstalled | Should -Not -BeNullOrEmpty
    }

    # Check for bad workspace
    It 'Should output a failure if the workspace is not accessible' {
        $results = @(Invoke-DQVTests -workspaceName "$($Variables.TestWorkspaceName)Bad" `
                        -credential $credentials `
                        -tenantId $variables.TestTenantId `
                        -logOutput "Table")

        $errors = $results | Where-Object {$_.logType -eq 'Error'}
        $errors.Length | Should -BeGreaterThan 0
        $errors[0].message.StartsWith("Cannot find workspace") | Should -Be $true
    }    

    # Check for good workspace
    It 'Should output one failure for a failed test' {
        $results = @(Invoke-DQVTests -workspaceName "$($Variables.TestWorkspaceName)" `
                        -credential $credentials `
                        -tenantId $variables.TestTenantId `
                        -logOutput "Table")
        
                        
        $errors = $results | Where-Object {$_.logType -eq 'Error'}
        $errors.Length | Should -BeGreaterThan 0
    }      

    # Check for good workspace
    It 'Should output a warning because the semantic model does not have tests' {

        $datasetIds = $variables.TestDatasetIdsDNE

        $results = @(Invoke-DQVTests -workspaceName "$($Variables.TestWorkspaceName)" `
                        -credential $credentials `
                        -tenantId $variables.TestTenantId `
                        -datasetId $datasetIds `
                        -logOutput "Table")
        
        Write-Host ($results | Format-Table | Out-String)
        $errors = $results | Where-Object {$_.logType -eq 'Warning'}
        $errors.Length | Should -BeGreaterThan 0
    }        

}