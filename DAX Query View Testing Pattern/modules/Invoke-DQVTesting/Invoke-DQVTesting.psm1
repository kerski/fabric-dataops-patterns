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
        version = "19.84.1"
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

# Check to see if the type already exists
# This is used identify which Power BI Reports are opened locally
if("UserWindows" -as [type])
{
    #already exists
}
else {
    <# Action when all if and elseif conditions are false #>
    Add-Type -IgnoreWarnings @"
using System;
using System.Runtime.InteropServices;
public class UserWindows {
[DllImport("user32.dll")]
public static extern IntPtr GetWindowText(IntPtr hWnd, System.Text.StringBuilder text, int count);
}
"@
}#end if

function Write-ToLog {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [Parameter(Mandatory = $false)]
        [ValidateSet('Debug','Warning','Error','Passed','Failure','Success')]
        [string]$LogType = 'Debug',
        [Parameter(Mandatory = $false)]
        [ValidateSet('ADO','Host','Table')]
        [string]$LogOutput = 'ADO',
        [Parameter(Mandatory = $false)]
        [bool]$IsTestResult = $false,
        [Parameter(Mandatory = $false)]
        [string]$DataSource="",
        [Parameter(Mandatory = $false)]
        [string]$ModelName=""
    )
    # Set prefix
    $prefix = ''

    if($LogOutput -eq 'Table'){
        $temp = @([pscustomobject]@{Message=$Message;LogType=$LogType;IsTestResult=$IsTestResult;DataSource=$DataSource;ModelName=$ModelName})
        $script:messages += $temp
    }
    elseif($LogOutput -eq 'ADO'){
        $prefix = '##[debug]'
        # Set prefix
        switch($LogType){
            'Warning' { $prefix = "##vso[task.logissue type=warning]"}
            'Error' { $prefix = "##vso[task.logissue type=error]"}
            'Failure' { $prefix = "##vso[task.complete result=Failed;]"}
            'Success' { $prefix = "##vso[task.complete result=Succeeded;]"}
        }
        # Add prefix and write to host
        $Message = $prefix + $Message
        Write-Output $Message
    }
    else{
        $color = "White"
        # Set prefix
        switch($LogType){
            'Warning' { $color = "Yellow"}
            'Error' { $color = "Red"}
            'Failure' { $color = "Red"}
            'Success' { $color = "Green"}
            'Passed' { $color = "Green"}
        }
        Write-Host -ForegroundColor $color $Message
    }
} #end Write-ToLog

<#
    .SYNOPSIS
    This module runs through the DAX Query View files that end with .Tests or .Test and output the results.  This is based on following the DAX Query View Testing Pattern: https://github.com/kerski/fabric-dataops-patterns/blob/main/DAX%20Query%20View%20Testing%20Pattern/dax-query-view-testing-pattern.md
    .DESCRIPTION
    The provided PowerShell script facilitates Data Query View (DQV) testing for datasets within a Fabric workspace.

    Tests should follow the DAX Query View Testing Pattern that returns a table with 4 column "TestName", "ExpectedValue", "ActualValue", "Passed".

    For more information, please visit this link: https://github.com/kerski/fabric-dataops-patterns/blob/main/DAX%20Query%20View%20Testing%20Pattern/dax-query-view-testing-pattern.md

    .PARAMETER Local
    When this switch is used, this module will identify the Power BI files opened on your local machine (opened with Power BI Desktop) and run tests associated with the opened Power BI Files.
    The purpose of this switch is to allow you to test locally before automated testing occurs in a Continous Integration pipeline.

    When the Local parameter is used, TenantId, WorkspaceName, and Credential parameter is not required.

    .PARAMETER Path
    Specifies paths to files containing tests. The value is a path\file name or name pattern. Wildcards are permitted.

    .PARAMETER TenantId
    The ID of the tenant where the Power BI workspace resides.

    .PARAMETER WorkspaceName
    The name of the Power BI workspace where the datasets are located.

    .PARAMETER Credential
    A PSCredential object containing the credentials used for authentication.

    .PARAMETER DatasetId
    An optional array of dataset IDs to specify which datasets to test. If not provided, all datasets will be tested.

    .PARAMETER LogOutput
    Specifies where the log messages should be written. Options are 'ADO' (Azure DevOps Pipeline), 'Host', or 'Table'.

    When ADO is chosen:
    - Any warning will be logged as an warning in the pipeline.  An example of a warning would be
    if a dataset/semantic model has no tests to conduct.
    - Any failed tests will be logged as an error in the pipeline.
    - Successfully tests will be logged as a debug in the pipeline.
    - If at least one failed test occurs, a failure is logged in the pipeline.

    When Host is chosen, all output is written via the Write-Output command.

    When Table is chosen:
    - An Array containing objects with the following properties:
        - Message (String): The description of the event.
        - LogType (String): This is either Debug, Warning, Error, or Failure.
        - IsTestResult (Boolean): This indicates if the event was a test or not.  This is helpful for filtering results.
        - DataSource: The location of the workspace (if in the service) or the localhost (if local testing) of the semantic model.
        - ModelName: The name of the semantic model.

    .PARAMETER CI
    Enable Exit after Run. When this switch is enable this will execute an "exit #" at the end of the module where "#" is the number of failed test cases.

    .EXAMPLE
    Run tests for all datasets/semantic models in the workspace and log output using Azure DevOps' logging commands.
    Invoke-DQVTesting -WorkspaceName "WORKSPACE_NAME" `
                        -Credential $userCredentials `
                        -TenantId "TENANT_ID" `
                        -LogOutput "ADO"

    .EXAMPLE
    Run tests for specific datasets/semantic models in the workspace and log output using Azure DevOps' logging commands.
    Invoke-DQVTesting -WorkspaceName "WORKSPACE_NAME" `
                        -Credential $userCredentials `
                        -TenantId "TENANT_ID" `
                        -DatasetId @("DATASET GUID1","DATASET GUID2") `
                        -LogOutput "ADO"

    .EXAMPLE
    Run tests for specific datasets/semantic models in the workspace and return output in an array of objects (table).
    Invoke-DQVTesting -WorkspaceName "WORKSPACE_NAME" `
                        -Credential $userCredentials `
                        -TenantId "TENANT_ID" `
                        -DatasetId @("DATASET GUID1","DATASET GUID2") `
                        -LogOutput "Table"

    .EXAMPLE
    Run tests for specific datasets/semantic models in the workspace and in subdirectories with names that begin with 'Model'.
    Output will use Azure DevOps' logging commands.
    Invoke-DQVTesting -WorkspaceName "WORKSPACE_NAME" `
                        -Credential $userCredentials `
                        -TenantId "TENANT_ID" `
                        -DatasetId @("DATASET GUID1","DATASET GUID2") `
                        -LogOutput "ADO" `
                        -Path ".\Model*"

    .EXAMPLE
    Run tests for specific datasets/semantic models opened locally (via Power BI Desktop) and return output in an array of objects (table).
    Invoke-DQVTesting -Local


    .EXAMPLE
    Run tests for specific datasets/semantic models opened locally (via Power BI Desktop) and execute tests only in subdirectories with names that begin with 'Model'.
    Returns output in an array of objects (table).
    Invoke-DQVTesting -Local -Path ".\Model*"

    .NOTES
        Author: John Kerski
        Dependencies:  PowerShell modules Az.Accounts is required.
        Power BI environment must be a Premium or Fabric capacity and the account must have access to the workspace and datasets.
        This script depends on FabricPS-PBIP which resides in Microsoft's Analysis Services GitHub site.
#>
function Invoke-DQVTesting  {
    [CmdletBinding(DefaultParameterSetName="Default")]
    [OutputType([System.Object[]])]
    param (
        [Parameter(Mandatory = $true, ParameterSetName="Local")]
        [switch]$Local,

        [Parameter(ParameterSetName = "Default")]
        [Parameter(ParameterSetName="Local")]
        [Parameter(Mandatory = $false)]
        [string]$Path = ".",

        [Parameter(Mandatory = $false, ParameterSetName = "Default")] # Mandatory if not local
        [string]$TenantId,

        [Parameter(Mandatory = $false, ParameterSetName = "Default")] # Mandatory if not local
        [string]$WorkspaceName,

        [Parameter(Mandatory = $false, ParameterSetName = "Default")] # Mandatory if not local
        [PSCredential]$Credential,

        [Parameter(Mandatory = $false, ParameterSetName = "Default")] # Ignored if Local
        [array]$DatasetId = @(),

        [Parameter(ParameterSetName = "Default")]
        [Parameter(ParameterSetName="Local")]
        [Parameter(Mandatory = $false)]
        [ValidateSet('ADO','Host','Table')] # Override to host if Local
        [string]$LogOutput = 'ADO',

        [Parameter(Mandatory = $false, ParameterSetName = "Default")]
        [switch]$CI
    )
    # Setup TLS 12
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    # Handle if local or not
    if($Local -eq $true){
        if($LogOutput -eq "ADO"){
            # Override to Host
            $LogOutput = "Host"
        }
    }else{
        # Check Tenant ID
        if(-not $TenantId){
            throw "TenantId Parameter is required when Local flag is false"
        }

        # Check Workspace Name
        if(-not $WorkspaceName){
            throw "Workspace Name Parameter is required when Local flag is false"
        }
        # Check Credentials
        if(-not $Credential){
            throw "Credential Parameter is required when Local flag is false"
        }
    }

    # Message Table
    $script:messages = @()

    # Initialize Datasets To Test
    $datatsetsToTest = @()

    # ---------- Identify Semantic Models for Testing ---------- #
    if($Local){ # Local

        # Find all opened PBI Files ==> x
        $datatsetsToTest = Get-PowerBIFilesOpened
    }else{ # Not Local

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

            # Temp Datasets to help with filtering
            $tempDatasets = @()
            # Make sure to check array
            $idsToCheck = @($DatasetId)

            foreach($id in $idsToCheck){
                Write-ToLog -Message "Checking if list of dataset ids exist in the workspace. Dataset ID: $($id -join ",")" `
                -LogType "Debug" `
                -LogOutput $LogOutput

                $temp = $datasets | Where-Object {$_.Id -eq $id}
                if($temp){# only add to array if id matches
                    $tempDatasets+=$temp
                }
            }# end for each

            # Reassign datasets with filtered down data
            $datasets = @($tempDatasets)

            if($datasets.Length -eq 0){
                Write-ToLog -Message "No datasets found in workspace from this list of dataset IDs: $($DatasetId)" `
                -LogType "Warning" `
                -LogOutput $LogOutput
            }# end count check
        }# end check for specific dataset ids passed in

        # Now compile information for testing the datasets in the workspace
        $counter = 0
        foreach($d in $datasets){
            # Setup initial information in temp object
            $temp = [pscustomobject]@{Id = $d.Id; Title = $d.displayName; Port = $null; DatabaseName=$d.displayName; Index = $counter; ConnectionString="" }
            # Setup Connection String Information
            # Handle connection string depending on a user account or service principal
            if($isServicePrincipal){
                # Add new testing object for service principal
                $datatsetsToTest += New-TestingObj -Id $d.Id `
                                                -ModelName $d.displayName `
                                                -Datasource "$($script:xMLAPrefix)$($WorkspaceName)" `
                                                -Database $d.displayName `
                                                -Credential $Credential `
                                                -ServicePrincipal `
                                                -TenantId $TenantId
            }
            else{
                # Add new testing object
                $datatsetsToTest += New-TestingObj -Id $d.Id `
                                                -ModelName $d.displayName `
                                                -Datasource "$($script:xMLAPrefix)$($WorkspaceName)" `
                                                -Database $d.displayName `
                                                -Credential $Credential
            }# end check of service principal
            $counter++;
        }# end foreach
    }# end check if local

    # ---------- Identify Metadata files for Semantic Models for Testing ---------- #
    $metadataObjs = Get-MetadataFileArray -Path $Path

    # ---------- Identify DAX Queries for Testing ---------- #
    # Initiate Failure Count
    $testsFailed = 0
    # Initiate Test Count
    $testCount = 0
    # Initiate Test Passed Count
    $testsPassed = 0
    foreach($datasetForTesting in $datatsetsToTest){

        Write-ToLog -Message "--------------------------------------------------" `
                    -LogType "Debug" `
                    -LogOutput $LogOutput
        Write-ToLog -Message "Attempting to run test files for $($datasetForTesting.ModelName)" `
                    -LogType "Debug" `
                    -LogOutput $LogOutput `
                    -DataSource $datasetForTesting.DataSource `
                    -ModelName $datasetForTesting.ModelName

        # Search metadataObjs
        $result = $metadataObjs | Where-Object {$_.DisplayName -eq $datasetForTesting.ModelName}

        if($result){ # We have a match so see if there are tests to conduct
            # Identify the DAX Queries that have a .Tests or .Test
            $testFiles = @(Get-ChildItem -Path "$($result[0].FolderPath)\DaxQueries" -Recurse | Where-Object {$_ -like "*.Tests.dax" -or $_ -like "*.Test.dax"})

            if($testFiles.Count -eq 0){
                Write-ToLog -Message "Unable to locate DAX files in this repository within ""$($Path)"". No tests will be conducted." `
                            -LogType "Warning" `
                            -LogOutput $LogOutput `
                            -DataSource $datasetForTesting.DataSource `
                            -ModelName $datasetForTesting.ModelName
                }else{
                # Execute Tests
                foreach($testFile in $testFiles){
                    Write-ToLog -Message "Running test file '$($testFile.FullName)'" `
                                -LogType "Debug" `
                                -LogOutput $LogOutput `
                                -DataSource $datasetForTesting.DataSource `
                                -ModelName $datasetForTesting.ModelName

                    # Create the Analysis Services connection object
                    $conn = New-Object Microsoft.AnalysisServices.AdomdClient.AdomdConnection

                    # Try issue query
                    Try{

                        # Assign connection string
                        $conn.ConnectionString = $datasetForTesting.ConnectionString

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
                        $rows = @($ds.Tables.Rows)
                        #Check if Row Count is 0, no test results.
                        if ($rows.Count -eq 0) {
                            $testsFailed += 1
                            Write-ToLog -Message "Query in test file ""$($testFile.FullName)"" returned no results." `
                                        -LogType "Error" `
                                        -LogOutput $LogOutput
                                        -DataSource $datasetForTesting.DataSource `
                                        -ModelName $datasetForTesting.ModelName
                        }#end check of results

                        # Check columns
                        $testNameColumnCheck= $null
                        $testNameColumnCheck = $ds.Tables.Columns | Where-Object {$_.ColumnName -eq "[TestName]"}
                        $passedNameColumnCheck = $null
                        $passedNameColumnCheck = $ds.Tables.Columns | Where-Object {$_.ColumnName -eq "[Passed]" }

                        if($testNameColumnCheck.Length -ne 1 -or $passedNameColumnCheck.Length -ne 1){
                            $testsFailed += 1
                            Write-ToLog -Message "Query in test file ""$($testFile.FullName)"" did not have test mandatory columns 'TestName', 'Passed')." `
                                        -LogType "Error" `
                                        -LogOutput $LogOutput `
                                        -DataSource $datasetForTesting.DataSource `
                                        -ModelName $datasetForTesting.ModelName
                        }else{
                            # Loop through each result
                            for($i = 0; $i -lt $rows.Count; $i++)
                            {
                                    # Increment Test Count
                                    $testCount +=1;
                                    #Extract Values
                                    $testName = $rows[$i]."[TestName]"
                                    $expectedVal = $rows[$i]."[ExpectedValue]"
                                    $actualVal = $rows[$i]."[ActualValue]"
                                    $passedStr = $rows[$i]."[Passed]".ToString()

                                    $passed = [bool]::Parse($passedStr)

                                    if (-not $passed) {
                                        $testsFailed += 1
                                        Write-ToLog -Message "FAILED!: Test ""$($testName)"" for semantic model: $($datasetForTesting.ModelName). Expected: $($expectedVal) != $($actualVal)" `
                                                    -LogType "Error" `
                                                    -LogOutput $LogOutput `
                                                    -IsTestResult $true `
                                                    -DataSource $datasetForTesting.DataSource `
                                                    -ModelName $datasetForTesting.ModelName
                                    }
                                    else {
                                        $testsPassed += 1
                                        Write-ToLog -Message """$($testName)"" passed. Expected: $($expectedVal) == $($actualVal)" `
                                                    -LogType "Passed" `
                                                    -LogOutput $LogOutput `
                                                    -IsTestResult $true `
                                                    -DataSource $datasetForTesting.DataSource `
                                                    -ModelName $datasetForTesting.ModelName
                                        }# end check not passed
                            }#end for loop
                        }#end column check
                    }Catch [System.Exception]{
                        $errObj = ($_).ToString()
                        Write-ToLog -Message "$($errObj)" `
                                    -LogType "Error" `
                                    -LogOutput $LogOutput
                        $testsFailed +=1
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
            Write-ToLog -Message "No test DAX queries for dataset '$($datasetForTesting.ModelName)' within ""$($Path)""." `
                        -LogType "Warning" `
                        -LogOutput $LogOutput `
                        -DataSource $datasetForTesting.DataSource `
                        -ModelName $datasetForTesting.ModelName
        }
    }# end foreach dataset

    # Handle output for final results
    $runResult = "Failure"
    if($testsFailed -eq 0){
        $runResult = "Success"
    }

    Write-ToLog -Message "Results: Tests Passed: $($testsPassed), Failed: $($testsFailed), Total Test Runs: $($testCount)." `
                -LogType $runResult `
                -LogOutput $LogOutput

    # Handle switch for CI
    if($CI){ # if sent output exit for failure count
        #TODO add parameter to documentation
        return $script:messages
        exit $testsFailed
    }else{
        return $script:messages
    }
}

<#
    .SYNOPSIS
    Identifies all metadata files for the datasets in the path provided.

    .DESCRIPTION
    Retrieve item.metadata.json files so we can map dataset names in the service with the name in the metadata files.
    March 2024 update - Handle updates for .SemanticModel and .platform changes

    .PARAMETER Path
    File Path to conduct search

    .OUTPUTS
    Array of objects with displayName and FolderPath members

    .EXAMPLE
    Looks for item.metadata.json and .platform files in datasets/semantic models for the current path and subfolders.
    Get-MetadataFileArray -Path "."
#>
Function Get-MetadataFileArray{
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    Process {
        $metadataObjs = @()

        Try{
            $metadataDS = Get-ChildItem -Path $Path -Recurse -Include "item.metadata.json",".platform" | `
            Where-Object {(Split-Path -Path $_.FullName).EndsWith(".Dataset") -or (Split-Path -Path $_.FullName).EndsWith(".SemanticModel")}

            foreach($m in $metadataDS){
                # Get Content on metdata
                $parentFolder = Split-Path -Path $m.FullName
                $content = Get-Content $m.FullName | ConvertFrom-Json

                # Handle item.metadata.json
                if($m.Name -eq 'item.metadata.json'){ # prior to March 2024 release
                    $temp = @([pscustomobject]@{DisplayName=$content.displayName;FolderPath=$ParentFolder;})
                }else{
                    $temp = @([pscustomobject]@{DisplayName=$content.metadata.displayName;FolderPath=$ParentFolder;})
                }

                $metadataObjs += $temp
            }# end for each
        }Catch [System.Exception]{
            $errObj = ($_).ToString()
            Write-ToLog -Message "$($errObj)" `
                        -LogType "Error" `
                        -LogOutput $LogOutput
        }# end try

        return $metadataObjs
    }# end process
}

<#
    .SYNOPSIS
    Identifies all the Power BI Reports opened on the current machine and identifies the ports.

    .DESCRIPTION
    This function iterates through each opened Power BI process and identifies the report and port that is opened.

    .PARAMETER Name
    Get-PowerBIFilesOpened

    .OUTPUTS
    Array of objects Testing Objects (see New-TestingObj)

    .EXAMPLE
    PS> $X = Get-PowerBIFilesOpened
    PS> $X[0] | Format-List
    PS>
    Name  : Port
    Value : 63402

    Name  : Title
    Value : Sample Report

    Name  : Id
    Value : 24480

    Name  : DatabaseName
    Value : f88de9a5-9849-4085-a3a2-5656cb42850f
#>
Function Get-PowerBIFilesOpened {
    [CmdletBinding()]
    Param()
    Process {
        #Get windows title and process ids for opened Power BI files
        $stringBuilder = New-Object System.Text.StringBuilder 256

        # Store custom objects with for testing later
        $testingObjs = @()
        # Index each local instance
        $counter = 0
        $pbiFileProcessIds = @()
        # Retrieve each process and grab instance of Power BI Desktop to identify local files opened
        Get-Process | ForEach-Object {
            $count = [UserWindows]::GetWindowText($_.MainWindowHandle, $stringbuilder, 256)

            if (0 -lt $count -and $_.Product -eq "Microsoft Power BI Desktop") {
                # Handle different versions of Power BI Desktop provideing Main Window Title formats
                if($_.MainWindowTitle.LastIndexOf('-') -gt 0){
                    $tempModel = $_.MainWindowTitle.Substring(0, $_.MainWindowTitle.LastIndexOf('-') - 1)
                }else{
                    $tempModel = $_.MainWindowTitle
                }# end if

                # Add custom object to array
                $pbiFileProcessIds += [pscustomobject]@{Id = $_.Id; Title = $tempModel; Port = 0; DatabaseName=""; Index = $counter }
                $counter++;
            }
        } # end ForEach-Object

        #Gets a list of the ProcessIDs for all Open Power BI Desktop files
        $processIds = $null
        Try{
            $processIds = Get-Process msmdsrv -ErrorAction Stop | Select-Object -ExpandProperty id
        }
        catch [System.SystemException]{
            Write-Output -ForegroundColor Red "No instances of Power BI are running on this machine."
        }
        # Loops through each ProcessIDs,
        # gets the diagnostic port for each file,
        # and finally generates the connection that can be use
        # when connecting to the Vertipaq model.
        if ($processIds) {
            foreach ($processId in $processIds) {
                $pbiDiagnosticPort = Get-NetTCPConnection | Where-Object { ($_.State -eq "Listen") -and ($_.RemoteAddress -eq "0.0.0.0") -and ($_.OwningProcess -eq $processId) } | Select-Object -ExpandProperty LocalPort
                # Get Parent Process Id
                $parentId = (Get-CimInstance -ClassName Win32_Process | Where-Object processid -eq $processId).parentprocessid
                $index = ($pbiFileProcessIds | Where-Object { $_.Id -eq $parentId }).Index
                if ($index -ge 0) {

                    # Setup Port Information
                    $pbiFileProcessIds[$index].Port = $pbiDiagnosticPort

                    # Now also get the database name
                    # Create the Analysis Services connection object
                    $conn = New-Object Microsoft.AnalysisServices.AdomdClient.AdomdConnection

                    # Try issue query
                    Try{
                        $conn.ConnectionString = "Provider=MSOLAP;Data Source=localhost:$($pbiDiagnosticPort)"
                        $conn.Open()
                        # Get query from file
                        $query = "select * from `$SYSTEM.DBSCHEMA_CATALOGS"
                        # Create the AS command
                        $cmd = New-Object -TypeName Microsoft.AnalysisServices.AdomdClient.AdomdCommand;
                        $cmd.Connection = $conn;
                        $cmd.CommandTimeout = 600;
                        $cmd.CommandText = $query

                        # Fill a dataset object with the result of the cmd
                        $da = new-Object Microsoft.AnalysisServices.AdomdClient.AdomdDataAdapter($cmd)
                        $ds = new-Object System.Data.DataSet
                        $x = $da.Fill($ds)
                        $rows = $ds.Tables.Rows

                        # We expect one row with the catalog name
                        $pbiFileProcessIds[$index].DatabaseName = $rows[0]
                        # Setup new testing object
                        $testingObjs += New-TestingObj -Id $pbiFileProcessIds[$index].Id `
                                                       -ModelName $pbiFileProcessIds[$index].Title `
                                                       -Datasource "localhost:$($pbiDiagnosticPort)" `
                                                       -Database $($rows[0])
                    }Catch [System.Exception]{
                        $errObj = ($_).ToString()
                        throw $errObj
                    }Finally{
                        #close your connection
                        $conn.Close();
                        $conn = $null;
                    }# end try
                }# check on index
            }# end foreach process id
        }# end check on process id array
        # Return array of objects with information about Power BI files opened
        # Make sure objects with data are returned
        return $testingObjs
    }#End Process
}#End Function

<#
    .SYNOPSIS
    Creates Testing Object to assist with conduct testing

    .DESCRIPTION
    Creates Testing Object to assist with conduct testing

    .PARAMETER Id
    Unique identified (typically GUID)

    .PARAMETER ModelName
    Name of the semantic model

    .PARAMETER DataSource
    Datasource as formatted for SSAS connection (ex. pbi://workspace, localhost:20481)

    .PARAMETER Database
    Database asformatted for SSAS connection. In local testing this is a GUID and why it's different from Model Name.

    .PARAMETER Credential
    Credential used for buidling connection string in the service (not local).

    .PARAMETER ServicePrincipal
    A switch that when provided alter hows the connection string is formatted.

    .PARAMETER TenantId
    Required when ServicePrincipal switch is supplied because it is required to build the connection string.

    .OUTPUTS
    Testing Object
#>
Function New-TestingObj  {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Id,
        [Parameter(Mandatory = $true)]
        [string]$ModelName,
        [Parameter(Mandatory = $true)]
        [string]$DataSource,
        [Parameter(Mandatory = $true)]
        [string]$Database,
        [Parameter(Mandatory = $false)]
        [PSCredential]$Credential,
        [Parameter(Mandatory = $false)]
        [switch]$ServicePrincipal,
        [Parameter(Mandatory = $false)] #Mandatory if ServicePrincipal is turned on
        [string]$TenantId
    )
    Process{
        #Initialize Temp Custom Object
        $temp = [pscustomobject]@{Id = $Id;ModelName = $ModelName;DataSource = $DataSource;Database = $Database;ConnectionString = "";}

        #Setup Connection String
        if($Credential){
            if($PSCmdlet.ShouldProcess,($Credential, 'Password will be placed as plain string in connection string. Please do not log to host without considering security implications.')){ # Assume not local
                # Convert secure string to plain text to use in connection strings
                $secureStringPtr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Credential.Password)
                $plainTextPwd = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($secureStringPtr)

                if($ServicePrincipal){
                    # Check Tenant ID
                    if(-not $TenantId){
                        throw "TenantId Parameter is required when ServicePrincipal flag is true"
                    }
                    $temp.ConnectionString = "Provider=MSOLAP;Data Source=$($DataSource);Database=$($Database);User ID=""app:$($Credential.UserName)@$($TenantId)"";Password=$plainTextPwd;Integrated Security=ClaimsToken;"
                }
                else{
                    $temp.ConnectionString = "Provider=MSOLAP;Data Source=$($DataSource);Database=$($Database);User ID=$($Credential.UserName);Password=$plainTextPwd;Integrated Security=ClaimsToken;"
                }# end check of service principal
            }
        }else{
            $temp.ConnectionString = "Provider=MSOLAP;Data Source=$($DataSource);Database=$($Database);"
        }# end Credential check
        return $temp
    } # end process
}# end New-TestingObj

Export-ModuleMember -Function Invoke-DQVTesting