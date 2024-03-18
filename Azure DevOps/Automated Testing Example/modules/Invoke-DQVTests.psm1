<#  
    Author: John Kerski  
  
    .DESCRIPTION: This module runs through the DAX Query View files that end with .Tests  
    or .Test and output the results.  
  
    Dependencies:  PowerShell modules Az.Accounts is required.  
  
    Power BI environment must be a Premium or Fabric capacity and the account must have access to the workspace and datasets.  
#>  

# Assumes commercial environment
$script:pbiAPIURL = "https://api.powerbi.com"

# Create a new directory in the current location
if((Test-Path -path ".\modules") -eq $false){
    New-Item -Name "modules" -Type Directory
}

# For each url download and install in module folder
@("https://raw.githubusercontent.com/microsoft/Analysis-Services/master/pbidevmode/fabricps-pbip/FabricPS-PBIP.psm1",
    "https://raw.githubusercontent.com/microsoft/Analysis-Services/master/pbidevmode/fabricps-pbip/FabricPS-PBIP.psd1") |% {
    Invoke-WebRequest -Uri $_ -OutFile ".\modules\$(Split-Path $_ -Leaf)"
}

# Import FabricPS-PBIP
Import-Module ".\modules\FabricPS-PBIP" -Force       

function Write-Log {
    param (
        [Parmaeter(Mandatory = $true)]
        [string]$message,
        [Parameter(Mandatory = $false)]
        [ValidateSet('Debug','Warning','Error')]
        [string]$logType = 'Debug',
        [Parameter(Mandatory = $false)]
        [ValidateSet('ADO','Host','Table')]
        [bool]$logOutput = 'ADO'
    )
    # Set prefix
    $prefix = ''

    if($logOutput -eq 'ADO'){
        $prefix = '##[debug]' 
        # Set prefix
        switch($logType){
            'Warning' { $prefix = "##vso[task.logissue type=warning]"}
            'Error' { $prefix = "##vso[task.logissue type=error]"}
        }

        # Add prefix and write to host
        $message = $prefix + $message
        Write-Host $message
    }
    else{
        Write-Host $message
    }
} #end Write-Log

function Invoke-DQVTests  {  
    param (  
        [Parameter(Mandatory = $true)]  
        [string]$path,  
          
        [Parameter(Mandatory = $true)]  
        [string]$workspaceId,  
          
        [Parameter(Mandatory = $true)]  
        [PSCredential]$credential,           
        
        [Parameter(Mandatory = $false)]  
        [array]$datasetId, 

        [Parameter(Mandatory = $false)]  
        [bool]$logWithADO = $true        
    )  
  
    # Setup TLS 12  
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12  
  
    # Setup Log Output
    $logOutput = "ADO"

    if($logWthADO -eq $false){
        $logOutput = "Host"
    }

    # Check if service principal or username/password  
    $guidRegex = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'  
    $isServicePrincipal = $false

    if($credential.UserName -match $guidRegex){# Service principal used  
        $isServicePrincipal = $true
    }  

    # Set Fabric Connection  
    Set-FabricAuthToken -credential $credential -tenantId $tenantId -reset      
  

    # Retrieve workspace name using filter capability
    Try{
        $workspaceObj = Get-FabricWorkspace -workspaceName $workspaceId
        $workspaceGuid = $workspaceObj.id
    }Catch [System.Exception]{
        $errObj = ($_).ToString()
        Write-Log -message "$($errObj)" -logType "Error" -logOutput $logOutput
    }# End Try

<# Retrieve items from the workspace
$workspaceItems = Invoke-FabricAPIRequest -Uri "workspaces/$workspaceGuid/items" -Method Get
$datasets = $workspaceItems | Where-Object {$_.type -eq "SemanticModel"} 

if($opts.DatasetIdsToTest){ # Filter datasets to test specifically base 
    Write-Host "##[debug]--------------------------------------------------"
    Write-Host "##[debug]Checking if list of dataset ids exist in workspace: $($opts.DatasetIdsToTest)"

    # Convert comma delimited string to array
    $idsToCheck = @($opts.DatasetIdsToTest.Trim() -split ",")

    $datasetsToTest = @()

    foreach($id in $idsToCheck){
        $temp = $datasets | Where-Object {$_.Id -eq $id}
        if($temp){# only add to array if id matches
            $datasetsToTest+=$temp
        }
    }# end for each

    # Reassign 
    $datasets = @($datasetsToTest)

    if($datasets.Length -eq 0){
        Write-Host "##vso[task.logissue type=warning]No datasets found in workspace from this list of workspace IDs: $($opts.DatasetIdsToTest)"
    }# end count check
}# end check for specific dataset ids passed in


# Retrieve item.metadata.json files so we can map dataset names in the service
# with the name in the metadata files
$metadataObjs = @()
$metadataDS = @(Get-ChildItem -Path "*.Dataset/item.metadata.json" -Recurse)

foreach($m in $metadataDS){
    # Get Content on metdata
    $parentFolder = Split-Path -Path $m.FullName
    $content = Get-Content $m.FullName | ConvertFrom-Json
    $temp = @([pscustomobject]@{displayName=$content.displayName;FolderPath=$ParentFolder;})
    $metadataObjs += $temp
}# end for each

# ---------- Identify DAX Queries for Testing ---------- #
foreach($dataset in $datasets){
    Write-Host "##[debug]--------------------------------------------------"
    Write-Host "##[debug]Attempting to run test files for $($dataset.displayName)"

    # Search metdataObjs
    $result = $metadataObjs | Where-Object {$_.displayName -eq $dataset.displayName}

    if($result){ # We have a match so see if there are tests to conduct
        # Identify the DAX Queries that have a .Tests or .Test
        $testFiles = @(Get-ChildItem -Path "$($result.FolderPath)/DaxQueries" -Recurse | Where-Object {$_ -like "*.Tests.dax" -or $_ -like "*.Test.dax"})

        if($testFiles.Count -eq 0){
            Write-Host "##vso[task.logissue type=warning]Unable to locate DAX files in this repository. No tests will be conducted."
        }else{
            # Execute Tests
            foreach($testFile in $testFiles){
                Write-Host "##[debug]Running test file '$($testFile.FullName)'"

                # Connect to XMLA EndPoint and run DAX Query
                Try {
                        # Get Token before each run of test
                        $authToken = Get-FabricAuthToken
                        $fabricHeaders = @{
                            'Content-Type' = "application/json"
                            'Authorization' = "Bearer {0}" -f $authToken
                        }

                        $requestUrl = "$($opts.PowerBIURL)/v1.0/myorg/groups/$($workspaceGuid)/datasets/$($dataset.Id)/executeQueries"
                        
                        # Retrieve Content of the test
                        $testContent = Get-Content $testFile.FullName -Raw

                        # Build request
                        $requestBody = @{
                            queries =@(
                                @{
                                    query = "$($testContent)"
                                }
                            )
                            serializerSettings = @{includeNulls = $false}
                        }

                        # Convert to Json
                        $requestBodyAsJson = $requestBody | ConvertTo-Json
                        
                        # Send Query
                        $requestResult = $null
                        $requestResult = Invoke-WebRequest -Headers $fabricHeaders `
                                                        -Uri $requestUrl `
                                                        -Method POST `
                                                        -Body $requestBodyAsJson

                        # Parse results
                        $requestResultJSON = $requestResult | ConvertFrom-Json

                        # Check if Row Count is 0, no test results.
                        if ($requestResultJSON.results.tables.rows.Count -eq 0) {
                            $failureCount += 1
                            Write-Host "##vso[task.logissue type=error]Query in test file ""$($testFile.FullName)"" returned no results."
                        }# end check of results

                        # Iterate through each row of the query results and check test results
                        $rowsToCheck = $requestResultJSON.results.tables.rows
                        foreach ($row in $rowsToCheck){
                            # Assign values
                            Write-Host $row
                            $testName = $row."[TestName]"
                            $passedStr = $row."[Passed]"

                            if (!$testName -or !$passedStr) {
                                $failureCount += 1
                                Write-Host "##vso[task.logissue type=error]Query in test file ""$($testFile.FullName)"" did not have test mandatory columns 'TestName', 'Passed')."
                            }
                            else {

                                $expectedVal = $row."[ExpectedValue]"
                                $actualVal = $row."[ActualValue]"

                                $passed = [bool]::Parse($passedStr)

                                if (-not $passed) {
                                    $failureCount += 1
                                    Write-Host "##vso[task.logissue type=error]FAILED!: Test ""$($testName)"" for semantic model: $($datasetName). Expected: $($expectedVal) != $($actualVal)" 
                                }
                                else {
                                    Write-Host "##[debug]""$($testName)"" passed. Expected: $($expectedVal) == $($actualVal)"
                                }
                            }
                            
                        }# end foreach
                }Catch [System.Exception]{
                    $errObj = ($_).ToString()
                    Write-Host "##vso[task.logissue type=error]$($errObj)"
                    $failureCount +=1
            }# end try
            }# end for each test file
        }# end on test file counts
}# end check metadata exists in this file structure for the dataset in the workspace
else
{
    Write-Host "##[debug]No test DAX queries for dataset '$($dataset.displayName)'."
}
}# end foreach dataset

# Check failure count
if($failureCount -gt 0){
exit 1 # Fail pipeline
}#>
}  
  
Export-ModuleMember -Function Invoke-DQVTests  