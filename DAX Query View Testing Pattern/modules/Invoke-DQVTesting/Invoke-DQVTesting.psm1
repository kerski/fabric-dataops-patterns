# Assumes commercial environment
$script:pbiAPIURL = "https://api.powerbi.com"
$script:xMLAPrefix = "powerbi://api.powerbi.com/v1.0/myorg/"
$script:messages = @()

#Install Az.Accounts if Needed
if (!(Get-Module -ListAvailable -Name "Az.Accounts")) {
    #Install Az.Accounts Module
    Install-Module -Name Az.Accounts -Scope CurrentUser -AllowClobber -Force
}

# Load the type from the Microsoft.AnalysisServices.AdomdClient nuget package
$currentPath = (Split-Path $MyInvocation.MyCommand.Definition -Parent)

$nugets = @(
    @{
        name = "Microsoft.AnalysisServices.AdomdClient.NetCore.retail.amd64"
        ;
        version = "19.77.0"
        ;
        path = @("lib\netcoreapp3.0\Microsoft.AnalysisServices.AdomdClient.dll",
                 "lib\netcoreapp3.0\Microsoft.AnalysisServices.Runtime.Core.dll",
                 "lib/netcoreapp3.0/Microsoft.AnalysisServices.Runtime.Windows.dll")
    }
)

foreach ($nuget in $nugets)
{
    Write-Output "Downloading and installing Nuget: $($nuget.name)"

    if (!(Test-Path "$currentPath\.nuget\$($nuget.name)*" -PathType Container)) {
        Install-Package -Name $nuget.name -ProviderName NuGet -Destination "$currentPath\.nuget" -RequiredVersion $nuget.Version -SkipDependencies -AllowPrereleaseVersions -Scope CurrentUser -Force
    }

    foreach ($nugetPath in $nuget.path)
    {
        Write-Output "Loading assemblies of: '$($nuget.name)'"

        $path = Resolve-Path (Join-Path "$currentPath\.nuget\$($nuget.name).$($nuget.Version)" $nugetPath)

        Add-Type -Path $path -Verbose | Out-Null
    }
}

# Create a new directory in the current location
if((Test-Path -path ".\.nuget\custom_modules") -eq $false){
    New-Item -Name ".nuget\custom_modules" -Type Directory
}

# For each url download and install in module folder
@("https://raw.githubusercontent.com/microsoft/Analysis-Services/master/pbidevmode/fabricps-pbip/FabricPS-PBIP.psm1",
    "https://raw.githubusercontent.com/microsoft/Analysis-Services/master/pbidevmode/fabricps-pbip/FabricPS-PBIP.psd1") | ForEach-Object {
    Invoke-WebRequest -Uri $_ -OutFile ".\.nuget\custom_modules\$(Split-Path $_ -Leaf)"
}

# Import FabricPS-PBIP
Import-Module ".\.nuget\custom_modules\FabricPS-PBIP" -Force

function Write-ToLog {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [Parameter(Mandatory = $false)]
        [ValidateSet('Debug','Warning','Error','Failure')]
        [string]$LogType = 'Debug',
        [Parameter(Mandatory = $false)]
        [ValidateSet('ADO','Host','Table')]
        [string]$LogOutput = 'ADO',
        [Parameter(Mandatory = $false)]
        [bool]$IsTestResult = $false
    )
    # Set prefix
    $prefix = ''

    if($LogOutput -eq 'Table'){
        $temp = @([pscustomobject]@{message=$Message;logType=$LogType;isTestResult=$IsTestResult})
        $script:messages += $temp
    }
    elseif($LogOutput -eq 'ADO'){
        $prefix = '##[debug]'
        # Set prefix
        switch($LogType){
            'Warning' { $prefix = "##vso[task.logissue type=warning]"}
            'Error' { $prefix = "##vso[task.logissue type=error]"}
            'Failure' { $prefix = "##vso[task.complete result=Failed;]"}
        }
        # Add prefix and write to host
        $Message = $prefix + $Message
        Write-Output $Message
    }
    else{
        Write-Output $Message
    }
} #end Write-ToLog

<#
    .SYNOPSIS
    This module runs through the DAX Query View files that end with .Tests or .Test and output the results.

    .DESCRIPTION
    The provided PowerShell script facilitates Data Query View (DQV) testing for datasets within a Fabric workspace.

    Tests should follow the DAX Query View Testing Pattern that returns a table with 4 column "TestName", "ExpectedValue", "ActualValue", "Passed".

    For more information, please visit this link: https://blog.kerski.tech/bringing-dataops-to-power-bi-part36/

    .PARAMETER TenantId
    The ID of the tenant where the Power BI workspace resides.

    .PARAMETER WorkspaceName
    The name of the Power BI workspace where the datasets are located.

    .PARAMETER Credential
    A PSCredential object containing the credentials used for authentication.

    .PARAMETER DatasetId
    An optional array of dataset IDs to specify which datasets to test. If not provided, all datasets will be tested.

    .PARAMETER LogOutput
    Specifies where the log messages should be output. Options are 'ADO' (Azure DevOps Pipeline), 'Host', or 'Table'.

    .EXAMPLE
    Run tests for all datasets/semantic models in the workspace
    Invoke-DQVTesting -WorkspaceName "WORKSPACE_NAME" `
                        -Credential $userCredentials `
                        -TenantId "TENANT_ID" `
                        -LogOutput "ADO"

    .EXAMPLE
    Run tests for specific datasets/semantic models in the workspace
    Invoke-DQVTesting -WorkspaceName "WORKSPACE_NAME" `
                        -Credential $userCredentials `
                        -TenantId "TENANT_ID" `
                        -DatasetId @("DATASET GUID1","DATASET GUID2") `
                        -LogOutput "ADO"

    .NOTES
        Author: John Kerski
        Dependencies:  PowerShell modules Az.Accounts is required.
        Power BI environment must be a Premium or Fabric capacity and the account must have access to the workspace and datasets.
        This script depends on FabricPS-PBIP which resides in Microsoft's Analysis Services GitHub site.
#>
function Invoke-DQVTesting  {
    param (
        [Parameter(Mandatory = $true)]
        [string]$TenantId,

        [Parameter(Mandatory = $true)]
        [string]$WorkspaceName,

        [Parameter(Mandatory = $true)]
        [PSCredential]$Credential,

        [Parameter(Mandatory = $false)]
        [array]$DatasetId = @(),

        [Parameter(Mandatory = $false)]
        [ValidateSet('ADO','Host','Table')]
        [string]$LogOutput = 'ADO'
    )
    # Setup TLS 12
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    # Check if service principal or username/password
    $guidRegex = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
    $isServicePrincipal = $false

    if($Credential.UserName -match $guidRegex){# Service principal used
        $isServicePrincipal = $true
    }

    # Convert secure string to plain text to use in connection strings
    $secureStringPtr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Credential.Password)
    $plainTextPwd = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($secureStringPtr)

    # Set Fabric Connection
    Try{

        if($isServicePrincipal){
            Set-FabricAuthToken -servicePrincipalId $Credential.UserName `
                                -servicePrincipalSecret $plainTextPwd `
                                -tenantId $TenantId -reset
        }
        else{ # User account
            Set-FabricAuthToken -credential $Credential -tenantId $TenantId -reset
        }
    }Catch [System.Exception]{
        $errObj = ($_).ToString()
        Write-ToLog -Message "$($errObj)" -LogType "Error" -LogOutput $LogOutput
        return @($script:messages)
    }# End Try

    # Message Table
    $script:messages = @()
    # Retrieve workspace name using filter capability
    Try{
        $workspaceObj = Get-FabricWorkspace -workspaceName $WorkspaceName
        $workspaceGuid = $workspaceObj.id
    }Catch [System.Exception]{
        $errObj = ($_).ToString()
        Write-ToLog -Message "$($errObj)" -LogType "Error" -LogOutput $LogOutput
        return @($script:messages)
    }# End Try

    # Retrieve items from the workspace
    $workspaceItems = Invoke-FabricAPIRequest -Uri "workspaces/$workspaceGuid/items" -Method Get
    $datasets = $workspaceItems | Where-Object {$_.type -eq "SemanticModel"}

    if($DatasetId.Length -gt 0){ # Filter datasets to test specifically base
        Write-ToLog -Message "--------------------------------------------------" `
                    -LogType "Debug" `
                    -LogOutput $LogOutput

        $datasetsToTest = @()
        $idsToCheck = @($DatasetId)

        foreach($id in $idsToCheck){
            Write-ToLog -Message "Checking if list of dataset id exist in the workspace. Dataset ID: $($id)" `
            -LogType "Debug" `
            -LogOutput $LogOutput

            $temp = $datasets | Where-Object {$_.Id -eq $id}
            if($temp){# only add to array if id matches
                $datasetsToTest+=$temp
            }
        }# end for each

        # Reassign
        $datasets = @($datasetsToTest)

        if($datasets.Length -eq 0){
            Write-ToLog -Message "No datasets found in workspace from this list of dataset IDs: $($opts.DatasetIdsToTest)" `
            -LogType "Warning" `
            -LogOutput $LogOutput
        }# end count check
    }# end check for specific dataset ids passed in

    # Retrieve item.metadata.json files so we can map dataset names in the service
    # with the name in the metadata files
    $metadataObjs = @()
    $metadataDS = @(Get-ChildItem -Path "*.Dataset/item.metadata.json" -Recurse) + @(Get-ChildItem -Path "*/*.Dataset/item.metadata.json" -Recurse)

    foreach($m in $metadataDS){
        # Get Content on metdata
        $parentFolder = Split-Path -Path $m.FullName
        $content = Get-Content $m.FullName | ConvertFrom-Json
        $temp = @([pscustomobject]@{displayName=$content.displayName;FolderPath=$ParentFolder;})
        $metadataObjs += $temp
    }# end for each

    # ---------- Identify DAX Queries for Testing ---------- #
    # Initiate Failure Count
    $failureCount = 0

    foreach($dataset in $datasets){
        Write-ToLog -Message "--------------------------------------------------" `
                    -LogType "Debug" `
                    -LogOutput $LogOutput
        Write-ToLog -Message "Attempting to run test files for $($dataset.displayName)" `
                    -LogType "Debug" `
                    -LogOutput $LogOutput

        # Search metdataObjs
        $result = $metadataObjs | Where-Object {$_.displayName -eq $dataset.displayName}

        if($result){ # We have a match so see if there are tests to conduct
            # Identify the DAX Queries that have a .Tests or .Test
            $testFiles = @(Get-ChildItem -Path "$($result.FolderPath)/DaxQueries" -Recurse | Where-Object {$_ -like "*.Tests.dax" -or $_ -like "*.Test.dax"})

            if($testFiles.Count -eq 0){
                Write-ToLog -Message "Unable to locate DAX files in this repository. No tests will be conducted." `
                            -LogType "Warning" `
                            -LogOutput $LogOutput
                }else{
                # Execute Tests
                foreach($testFile in $testFiles){
                    Write-ToLog -Message "Running test file '$($testFile.FullName)'" `
                                -LogType "Debug" `
                                -LogOutput $LogOutput
                    # Setup Connection String Information
                    $serverAddress = "$($script:xMLAPrefix)$($WorkspaceName)"
                    $databaseName = $dataset.displayName
                    $userName = $Credential.UserName
                    $connPwd = $plainTextPwd

                    # Create the Analysis Services connection object
                    $conn = New-Object Microsoft.AnalysisServices.AdomdClient.AdomdConnection

                    # Try issue query
                    Try{

                        # Handle connection string depending on a user account or service principal
                        if($isServicePrincipal){
                            $conn.ConnectionString = "Provider=MSOLAP;Data Source=$serverAddress;Database=$databaseName;User ID=""app:$($userName)@$($TenantId)"";Password=$connPwd;Integrated Security=ClaimsToken;"
                        }
                        else{
                            $conn.ConnectionString = "Provider=MSOLAP;Data Source=$serverAddress;Database=$databaseName;User ID=$userName;Password=$connPwd;Integrated Security=ClaimsToken;"
                        }

                        $conn.Open()
                        # Get query from file
                        $query = (Get-Content $testFile.FullName -Raw)
                        # Create the AS command
                        $cmd = New-Object -TypeName Microsoft.AnalysisServices.AdomdClient.AdomdCommand;
                        $cmd.Connection = $conn;
                        $cmd.CommandTimeout = 600;
                        $cmd.CommandText = $query

                        # Fill a dataset object with the result of the cmd
                        $da = new-Object Microsoft.AnalysisServices.AdomdClient.AdomdDataAdapter($cmd)
                        $ds = new-Object System.Data.DataSet
                        $temp = $da.Fill($ds)
                        $rows = $ds.Tables.Rows
                        #Check if Row Count is 0, no test results.
                        if ($rows.Count -eq 0) {
                            $failureCount += 1
                            Write-ToLog -Message "Query in test file ""($testFile.FullName)"" returned no results." `
                                        -LogType "Error" `
                                        -LogOutput $LogOutput
                        }#end check of results

                        # Loop through each result
                        for($i = 0; $i -lt $rows.Count; $i++)
                        {
                                #Extract Values
                                $testName = $rows[$i]."[TestName]"
                                $expectedVal = $rows[$i]."[ExpectedValue]"
                                $actualVal = $rows[$i]."[ActualValue]"
                                $passedStr = $rows[$i]."[Passed]".ToString()

                                if (!$testName -or !$passedStr) {
                                    $failureCount += 1
                                    Write-ToLog -Message "Query in test file ""$($testFile.FullName)"" did not have test mandatory columns 'TestName', 'Passed')." `
                                    -LogType "Error" `
                                    -LogOutput $LogOutput
                                }
                                else {

                                    $passed = [bool]::Parse($passedStr)

                                    if (-not $passed) {
                                        $failureCount += 1
                                        Write-ToLog -Message "FAILED!: Test ""$($testName)"" for semantic model: $($databaseName). Expected: $($expectedVal) != $($actualVal)" `
                                                    -LogType "Error" `
                                                    -LogOutput $LogOutput `
                                                    -IsTestResult $true
                                    }
                                    else {
                                        Write-ToLog -Message """$($testName)"" passed. Expected: $($expectedVal) == $($actualVal)" `
                                                    -LogType "Debug" `
                                                    -LogOutput $LogOutput `
                                                    -IsTestResult $true
                                        }# end check not passed
                                }# end check on test name and passed
                        }#end for loop

                    }Catch [System.Exception]{
                        $errObj = ($_).ToString()
                        Write-ToLog -Message "$($errObj)" `
                                    -LogType "Error" `
                                    -LogOutput $LogOutput
                        $failureCount +=1
                    }Finally{
                        #close your connection
                        $conn.Close();
                        $conn = $null;
                    }# end try
                }# end for each test file
            }# end on test file counts
        }# end check metadata exists in this file structure for the dataset in the workspace
        else
        {
            Write-ToLog -Message "No test DAX queries for dataset '$($dataset.displayName)'." `
                        -LogType "Debug" `
                        -LogOutput $LogOutput
        }
    }# end foreach dataset

    if($LogOutput -eq "ADO"){
        if($failureCount -gt 0){
            Write-ToLog -Message "Number of Failed Tests: $($failureCount)." `
                        -LogType "Failure" `
                        -LogOutput $LogOutput
        }
    }
    return $script:messages
}

Export-ModuleMember -Function Invoke-DQVTesting