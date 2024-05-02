Describe 'Invoke-SemanticModelRefresh' {
    BeforeAll { 
        Import-Module ".\Invoke-SemanticModelRefresh\Invoke-SemanticModelRefresh.psm1" -Force

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
        $isInstalled = Get-Command Invoke-SemanticModelRefresh
        $isInstalled | Should -Not -BeNullOrEmpty
    }
    
    It 'Should Refresh Semantic Model with user credential' {

        $testSemanticModelId = $variables.TestDatasetMarch2024[0]

        $refreshResult = Invoke-SemanticModelRefresh -WorkspaceId $variables.TestWorkspaceId `
                                    -SemanticModelId  $testSemanticModelId `
                                    -Credential $userCredentials `
                                    -TenantId "$($variables.TestTenantId)" `
                                    -Environment Public `
                                    -LogOutput Host
        
        $refreshResult | Should -Be "Completed"
    }

    It 'Should fail to authenticate due to bad tenant Id' -Tag "ServicePrincipal" {

        $testSemanticModelId = $variables.TestDatasetMarch2024[0]

        $refreshResult = Invoke-SemanticModelRefresh -WorkspaceId $variables.TestWorkspaceId `
                                    -SemanticModelId  $testSemanticModelId `
                                    -Credential $serviceCredentials `
                                    -TenantId "x$($variables.TestTenantId)" `
                                    -Environment Public `
                                    -LogOutput Host

        $refreshResult | Should -Be "Failed"
    }  

    It 'Should Refresh Semantic Model with service credential' -Tag "ServicePrincipal" {

        $testSemanticModelId = $variables.TestDatasetMarch2024[0]

        $refreshResult = Invoke-SemanticModelRefresh -WorkspaceId $variables.TestWorkspaceId `
                                    -SemanticModelId  $testSemanticModelId `
                                    -Credential $serviceCredentials `
                                    -TenantId "$($variables.TestTenantId)" `
                                    -Environment Public `
                                    -LogOutput Host
        
        $refreshResult | Should -Be "Completed"
    }   
    
    It 'Should Fail Refresh Semantic Model given dataset id is bad' -Tag "ServicePrincipal" {

        $testSemanticModelId = "bad$($variables.TestDatasetMarch2024[0])"

        $refreshResult = Invoke-SemanticModelRefresh -WorkspaceId $variables.TestWorkspaceId `
                                    -SemanticModelId  $testSemanticModelId `
                                    -Credential $serviceCredentials `
                                    -TenantId "$($variables.TestTenantId)" `
                                    -Environment Public `
                                    -LogOutput host
        

        $refreshResult | Should -Be "Failed"
    }     

    It 'Should Fail to Refresh Semantic Model' {

        $testSemanticModelId = "x$($variables.TestDatasetMarch2024[0])"

        $refreshResult = Invoke-SemanticModelRefresh -WorkspaceId $variables.TestWorkspaceId `
                                    -SemanticModelId  $testSemanticModelId `
                                    -Credential $userCredentials `
                                    -TenantId "$($variables.TestTenantId)" `
                                    -Environment Public `
                                    -LogOutput Host

        $refreshResult | Should -Be "Failed"
    }    
}