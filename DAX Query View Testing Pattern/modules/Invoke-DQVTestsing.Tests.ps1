Describe 'Invoke-DQVTesting' {
    BeforeAll { 
        Import-Module .\Invoke-DQVTesting.psm1 -Force

        # Retrieve specific variables from json so we don't keep sensitive values in 
        # source control
        $variables = Get-Content .\Invoke-DQVTests.config.json | ConvertFrom-Json        
        $userSecret = $variables.TestPassword | ConvertTo-SecureString -AsPlainText -Force
        $serviceSecret = $variables.TestClientSecret | ConvertTo-SecureString -AsPlainText -Force
        $userCredentials = [System.Management.Automation.PSCredential]::new($variables.TestUserName,$userSecret)   
        $serviceCredentials = [System.Management.Automation.PSCredential]::new($variables.TestServicePrincipal,$serviceSecret)
    }

    # Clean up
    AfterAll {
    }
    
    # Check if File Exists
    It 'Module should exist' {
        $isInstalled = Get-Command Invoke-DQVTesting
        $isInstalled | Should -Not -BeNullOrEmpty
    }

    # Check for bad workspace
    It 'Should output a failure if the workspace is not accessible' {
        $results = @(Invoke-DQVTesting -WorkspaceName "$($Variables.TestWorkspaceName)Bad" `
                        -Credential $userCredentials `
                        -TenantId $variables.TestTenantId `
                        -LogOutput "Table")

        $errors = $results | Where-Object {$_.logType -eq 'Error'}
        $errors.Length | Should -BeGreaterThan 0
        $errors[0].message.StartsWith("Cannot find workspace") | Should -Be $true
    } 
    

    # Check for bad tenant id
    It 'Should output a failure if the tenant id is not accessible' {
        $results = @(Invoke-DQVTesting -WorkspaceName "$($Variables.TestWorkspaceName)Bad" `
                        -Credential $userCredentials `
                        -TenantId $variables.TestTenantId `
                        -LogOutput "Table")

        $errors = $results | Where-Object {$_.logType -eq 'Error'}
        $errors.Length | Should -BeGreaterThan 0
        $errors[0].message.StartsWith("Cannot find workspace") | Should -Be $true
    }     
    
    # Check for bad datasets
    It 'Should output a warning because the dataset ids passed do not exist in the workspace' {

        $datasetIds = @("192939-392840","192939-392332") # Bad Datasets

        $results = @(Invoke-DQVTesting -WorkspaceName "$($Variables.TestWorkspaceName)" `
                        -Credential $userCredentials `
                        -TenantId $variables.TestTenantId `
                        -DatasetId $datasetIds `
                        -LogOutput "Table")
        
        Write-Host ($results | Format-Table | Out-String)
        $warnings = $results | Where-Object {$_.logType -eq 'Warning'}
        $warnings.Length | Should -BeGreaterThan 0
        $warnings[0].message.StartsWith("No datasets found in workspace") | Should -Be $true 
    }      
    
    # Check for failed test
    It 'Should output one failure for a failed test' {
        $results = @(Invoke-DQVTesting -WorkspaceName "$($Variables.TestWorkspaceName)" `
                        -Credential $userCredentials `
                        -TenantId $variables.TestTenantId `
                        -LogOutput "Table")
        
                        
        $errors = $results | Where-Object {$_.logType -eq 'Error'}
        $errors.Length | Should -BeGreaterThan 0
    }     

    # Check for warning for datasets that don't have 
    It 'Should output a warning because the semantic models does not have tests' {

        $datasetIds = $variables.TestDatasetIdsDNE

        $results = @(Invoke-DQVTesting -WorkspaceName "$($Variables.TestWorkspaceName)" `
                        -Credential $userCredentials `
                        -TenantId $variables.TestTenantId `
                        -DatasetId $datasetIds `
                        -LogOutput "Table")
        
        Write-Host ($results | Format-Table | Out-String)
        $warnings = $results | Where-Object {$_.logType -eq 'Warning'}
        $warnings.Length | Should -BeGreaterThan 0
    }  
    
    # Check for warning for datasets that don't have 
    It 'Should run tests because the semantic models has tests that pass' {

        $datasetIds = $variables.TestDatasetIdsExist

        $results = @(Invoke-DQVTesting -WorkspaceName "$($Variables.TestWorkspaceName)" `
                        -Credential $userCredentials `
                        -TenantId $variables.TestTenantId `
                        -DatasetId $datasetIds `
                        -LogOutput "Table")
        
        Write-Host ($results | Format-Table | Out-String)
        $warnings = $results | Where-Object {$_.logType -eq 'Warning'}
        $warnings.Length | Should -Be 0
    }  

    # Check tests run with user account 
    It 'Should run tests because the semantic models has tests that pass using a service account' {

        $datasetIds = $variables.TestDatasetIdsExist

        $results = @(Invoke-DQVTesting -WorkspaceName "$($Variables.TestWorkspaceName)" `
                        -Credential $userCredentials `
                        -TenantId $variables.TestTenantId `
                        -DatasetId $datasetIds `
                        -LogOutput "Table")
        
        Write-Host ($results | Format-Table | Out-String)
        $warnings = $results | Where-Object {$_.logType -eq 'Warning'}
        $warnings.Length | Should -Be 0
        
        $testResults = $results | Where-Object {$_.isTestResult -eq $true}
        $testResults.Length | Should -BeGreaterThan 0
    }
    
    # Check tests run with service principal
    It 'Should run tests because the semantic models has tests that pass using a service principal' {

        $datasetIds = $variables.TestDatasetIdsExist

        $results = @(Invoke-DQVTesting -WorkspaceName "$($Variables.TestWorkspaceName)" `
                        -Credential $serviceCredentials `
                        -TenantId $variables.TestTenantId `
                        -DatasetId $datasetIds `
                        -LogOutput "Table")
        
        Write-Host ($results | Format-Table | Out-String)
        $warnings = $results | Where-Object {$_.logType -eq 'Warning'}
        $warnings.Length | Should -Be 0
        
        $testResults = $results | Where-Object {$_.isTestResult -eq $true}
        $testResults.Length | Should -BeGreaterThan 0
    }    

    # Check tests run with a service account with RLS semantic model
    It 'Should run tests because the RLS semantic models has tests that pass using a service account' {

        $datasetIds = $variables.TestDatasetIdsRLS

        $results = @(Invoke-DQVTesting -WorkspaceName "$($Variables.TestWorkspaceName)" `
                        -Credential $userCredentials `
                        -TenantId $variables.TestTenantId `
                        -DatasetId $datasetIds `
                        -LogOutput "Table")
        
        Write-Host ($results | Format-Table | Out-String)
        $warnings = $results | Where-Object {$_.logType -eq 'Warning'}
        $warnings.Length | Should -Be 0
        
        $testResults = $results | Where-Object {$_.isTestResult -eq $true}
        $testResults.Length | Should -Be 2
    }   
    
    # Check tests run with a service principal with RLS semantic model
    It 'Should run tests because the RLS semantic models has tests that pass using a service principal' {

        $datasetIds = $variables.TestDatasetIdsRLS

        $results = @(Invoke-DQVTesting -WorkspaceName "$($Variables.TestWorkspaceName)" `
                        -Credential $serviceCredentials `
                        -TenantId $variables.TestTenantId `
                        -DatasetId $datasetIds `
                        -LogOutput "Table")
        
        Write-Host ($results | Format-Table | Out-String)
        $warnings = $results | Where-Object {$_.logType -eq 'Warning'}
        $warnings.Length | Should -Be 0
        
        $testResults = $results | Where-Object {$_.isTestResult -eq $true}
        $testResults.Length | Should -Be 2
    }

    # Check for empty
    It 'Should run tests because the dataset ids is empty' {

        $datasetIds = @() # Empty Datasets

        $results = @(Invoke-DQVTesting -WorkspaceName "$($Variables.TestWorkspaceName)" `
                        -Credential $userCredentials `
                        -TenantId $variables.TestTenantId `
                        -DatasetId $datasetIds `
                        -LogOutput "Table")
                
        $testResults = $results | Where-Object {$_.isTestResult -eq $true}
        $testResults.Length | Should -BeGreaterThan 0
    }  
    
   # Check for bad query
   It 'Should raise error DAX query was not formatted correctly' {

    $datasetIds = $variables.BadQueryDatasetIds

    $results = @(Invoke-DQVTesting -WorkspaceName "$($Variables.TestWorkspaceName)" `
                    -Credential $userCredentials `
                    -TenantId $variables.TestTenantId `
                    -DatasetId $datasetIds `
                    -LogOutput "Table")
            
    Write-Host ($results | Format-Table | Out-String)
    $errors = $results | Where-Object {$_.logType -eq 'Error'}
    $errors.Length | Should -BeGreaterThan 0
}      

        
}