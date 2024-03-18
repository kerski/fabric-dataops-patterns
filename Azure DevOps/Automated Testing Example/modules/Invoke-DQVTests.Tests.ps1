Describe 'Invoke-DQVTests' {
    BeforeAll { 
        Import-Module .\Invoke-DQVTests.psm1 -Force

        # Retrieve specific variables from json so we don't keep sensitive values in 
        # source control
        $Variables = Get-Content .\Invoke-DQVTests.config.json | ConvertFrom-Json        

    }

    #Clean up
    AfterAll {
        Write-Host $Variables
    }

    #Check if File Exists
    It 'Module should exist' {
        $IsInstalled = Get-Command Invoke-DQVTests
        $IsInstalled | Should -Not -BeNullOrEmpty
    }

    #Check if File Exists
    It 'Module should exist' {
        Invoke-DQVTests -path ".\" -workspaceId $Variables.TestWorkspaceId -credential -datasetId -logWithADO
    }    

}