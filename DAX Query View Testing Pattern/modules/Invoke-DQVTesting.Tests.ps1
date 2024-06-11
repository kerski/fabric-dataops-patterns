Describe 'Invoke-DQVTesting' {
    BeforeAll { 
        Uninstall-Module -Name Invoke-DQVTesting -Force -ErrorAction SilentlyContinue
        Import-Module ".\Invoke-DQVTesting\Invoke-DQVTesting.psm1" -Force

        # Retrieve specific variables from json so we don't keep sensitive values in 
        # source control
        $variables = Get-Content .\Tests.config.json | ConvertFrom-Json        
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
    
    # Check for Local parameters
    # Make sure SampleTestMarch2024Release is open
    It 'Should run tests locally' -Tag "Local" {
        $results = @(Invoke-DQVTesting -Local -LogOutput "Table")
        
        Write-Host ($results | Format-Table | Out-String)
        $warnings = $results | Where-Object {$_.LogType -eq 'Warning' -and $_.ModelName -eq 'SampleTestMarch2024Release'}
        $warnings.Length | Should -Be 0
        
        $testResults = $results | Where-Object {$_.IsTestResult -eq $true}
        $testResults.Length | Should -BeGreaterThan 0
    }

    # No tests should be found for these tests
    # Make sure SampleTestMarch2024Release is open
    It 'Should warn about no test because path does not have tests for currently opened file' -Tag "Local" {
        $testPath = "$((pwd).Path)\testFiles\sub*"
        $results = @(Invoke-DQVTesting -Local -Path $testPath -LogOutput "Table")
        
        Write-Host ($results | Format-Table | Out-String)
        $warnings = $results | Where-Object {$_.LogType -eq 'Warning' -and $_.ModelName -eq "SampleTestMarch2024Release"}
        
        $warnings.Length | Should -BeGreaterThan 0
        
        $warnings[0].message.StartsWith("No test DAX queries") | Should -Be $true 
    }

    # No tests should be found for these tests
    # Make sure SampleTestMarch2024Release is open
    It 'Should run tests for a subset based on folder path "SampleTest"' -Tag "Local" {
        $testPath = "$((pwd).Path)\testFiles\Sample*"
        $results = @(Invoke-DQVTesting -Local -Path $testPath -LogOutput "Table")
        
        Write-Host ($results | Format-Table | Out-String)
        $testResults = $results | Where-Object {$_.IsTestResult -eq $true}
        $testResults.Length | Should -BeGreaterThan 0
    }    

    It 'Should run tests for a subset based on folder path "SampleTest"' -Tag "Local" {
        $testPath = "$((pwd).Path)\testFiles\Sample*"
        $results = Invoke-DQVTesting -Local -Path $testPath -LogOutput "Table"
       
        $testResults = $results | Where-Object {$_.IsTestResult -eq $true}
        $testResults.Length | Should -BeGreaterThan 0    
    }   

    # Check for missing tenant Id when not local
    It 'Should throw error is missing tenant id when not local' -Tag "NotLocal" {
        {Invoke-DQVTesting} | Should -Throw
    }

    # Check for missing tenant Id when not local
    It 'Should throw error is missing tenant id when not local' -Tag "NotLocal" {
        {Invoke-DQVTesting} | Should -Throw
    }    

    # Check for missing workspace when not local
    It 'Should throw error is missing workspace when not local' -Tag "NotLocal" {
        {Invoke-DQVTesting -TenantId $variables.TestTenantId} | Should -Throw
    }

    # Check for missing credentials when not local
    It 'Should throw error is missing credentials when not local' -Tag "NotLocal" {
        {Invoke-DQVTesting -TenantId $variables.TestTenantId -WorkspaceName "$($Variables.TestWorkspaceName)"} | Should -Throw
    }    

    # Check for March 2024 release .platform and .Semantic Model renames 
    It 'Should output test results with new .platform format' -Tag "March2024" {

        $datasetIds = $variables.TestDatasetMarch2024

        $results = @(Invoke-DQVTesting -WorkspaceName "$($Variables.TestWorkspaceName)" `
                        -Credential $userCredentials `
                        -TenantId $variables.TestTenantId `
                        -DatasetId $datasetIds `
                        -LogOutput "Table")
        
        Write-Host ($results | Format-Table | Out-String)
        $warnings = $results | Where-Object {$_.LogType -eq 'Warning'}
        $warnings.Length | Should -Be 0
        
        $testResults = $results | Where-Object {$_.IsTestResult -eq $true}
        $testResults.Length | Should -BeGreaterThan 0
    }        
    
    # Check for bad workspace
    It 'Should output a failure if the workspace is not accessible' {
        $results = @(Invoke-DQVTesting -WorkspaceName "$($Variables.TestWorkspaceName)Bad" `
                        -Credential $userCredentials `
                        -TenantId $variables.TestTenantId `
                        -LogOutput "Table")

        $errors = $results | Where-Object {$_.LogType -eq 'Error'}
        $errors.Length | Should -BeGreaterThan 0
        $errors[0].message.StartsWith("Cannot find workspace") | Should -Be $true
    } 
    

    # Check for bad tenant id
    It 'Should output a failure if the tenant id is not accessible' {
        $results = @(Invoke-DQVTesting -WorkspaceName "$($Variables.TestWorkspaceName)Bad" `
                        -Credential $userCredentials `
                        -TenantId $variables.TestTenantId `
                        -LogOutput "Table")

        $errors = $results | Where-Object {$_.LogType -eq 'Error'}
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
        $warnings = $results | Where-Object {$_.LogType -eq 'Warning'}
        $warnings.Length | Should -BeGreaterThan 0
        $warnings[0].message.StartsWith("No datasets found in workspace") | Should -Be $true 
    }      
    
    # Check for failed test
    It 'Should output one failure for a failed test' {
        $results = @(Invoke-DQVTesting -WorkspaceName "$($Variables.TestWorkspaceName)" `
                        -Credential $userCredentials `
                        -TenantId $variables.TestTenantId `
                        -LogOutput "Table")
        
                        
        $errors = $results | Where-Object {$_.LogType -eq 'Error'}
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
        $warnings = $results | Where-Object {$_.LogType -eq 'Warning'}
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
        $warnings = $results | Where-Object {$_.LogType -eq 'Warning'}
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
        $warnings = $results | Where-Object {$_.LogType -eq 'Warning'}
        $warnings.Length | Should -Be 0
        
        $testResults = $results | Where-Object {$_.IsTestResult -eq $true}
        $testResults.Length | Should -BeGreaterThan 0
    }
    
    # Check tests run with service principal
    It 'Should run tests because the semantic models has tests that pass using a service principal' -Tag "ServicePrincipal" {

        $datasetIds = $variables.TestDatasetIdsExist

        $results = @(Invoke-DQVTesting -WorkspaceName "$($Variables.TestWorkspaceName)" `
                        -Credential $serviceCredentials `
                        -TenantId $variables.TestTenantId `
                        -DatasetId $datasetIds `
                        -LogOutput "Table")
        
        Write-Host ($results | Format-Table | Out-String)
        $warnings = $results | Where-Object {$_.LogType -eq 'Warning'}
        $warnings.Length | Should -Be 0
        
        $testResults = $results | Where-Object {$_.IsTestResult -eq $true}
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
        $warnings = $results | Where-Object {$_.LogType -eq 'Warning'}
        $warnings.Length | Should -Be 0
        
        $testResults = $results | Where-Object {$_.IsTestResult -eq $true}
        $testResults.Length | Should -Be 2
    }   
    
    # Check tests run with a service principal with RLS semantic model
    It 'Should run tests because the RLS semantic models has tests that pass using a service principal' -Tag "ServicePrincipal" {

        $datasetIds = $variables.TestDatasetIdsRLS

        $results = @(Invoke-DQVTesting -WorkspaceName "$($Variables.TestWorkspaceName)" `
                        -Credential $serviceCredentials `
                        -TenantId $variables.TestTenantId `
                        -DatasetId $datasetIds `
                        -LogOutput "Table")
        
        Write-Host ($results | Format-Table | Out-String)
        $warnings = $results | Where-Object {$_.LogType -eq 'Warning'}
        $warnings.Length | Should -Be 0
        
        $testResults = $results | Where-Object {$_.IsTestResult -eq $true}
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
                
        $testResults = $results | Where-Object {$_.IsTestResult -eq $true}
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
    $errors = $results | Where-Object {$_.LogType -eq 'Error'}
    $errors.Length | Should -BeGreaterThan 0
    }      

    # Cjecl fpr 
    It 'Should output errors for bad tests' -Tag "BadTests" {

        $datasetIds = $variables.BadQueryDatasetIds

        $results = @(Invoke-DQVTesting -WorkspaceName "$($Variables.TestWorkspaceName)" `
                        -Credential $userCredentials `
                        -TenantId $variables.TestTenantId `
                        -DatasetId $datasetIds `
                        -LogOutput "Table")
        
        Write-Host ($results | Format-Table | Out-String)
        $errors = $results | Where-Object {$_.LogType -eq 'Error'}
        $errors.Length | Should -BeGreaterThan 1
    }    
 
    
    # Check tests run with one test for a user credentials
    It 'Should run a test because the semantic model has one test with one row using a user account' -Tag "SingleRow" {

        $datasetIds = $variables.TestSingleRowTest

        $results = @(Invoke-DQVTesting -WorkspaceName "$($Variables.TestWorkspaceName)" `
                        -Credential $userCredentials `
                        -TenantId $variables.TestTenantId `
                        -DatasetId $datasetIds `
                        -LogOutput "Table")
        
        Write-Host ($results | Format-Table | Out-String)
        $warnings = $results | Where-Object {$_.LogType -eq 'Warning'}
        $warnings.Length | Should -Be 0
        
        $testResults = $results | Where-Object {$_.IsTestResult -eq $true}
        $testResults.Length | Should -Be 1
    }


}