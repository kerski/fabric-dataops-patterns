Describe 'Invoke-DQVTesting' {
    BeforeAll { 
        Import-Module ".\.nuget\custom_modules\FabricPS-PBIP.psm1" -Force

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

        Set-FabricAuthToken -credential $userCredentials
        $X = Export-FabricItems -workspaceId $variables.TestWorkspaceId
        
        $isInstalled = Get-Command Get-FabricAuthToken
        $isInstalled | Should -Not -BeNullOrEmpty
    }    
    
    
        
}