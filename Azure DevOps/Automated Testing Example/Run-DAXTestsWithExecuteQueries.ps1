<#
    Author: John Kerski

    .DESCRIPTION: This pipeline code run through the DAX Query View files that end with .Tests
    or .Test and output the results.

    Dependencies:  PowerShell modules Az.Accounts and SqlServer version 22.0 is required.

    Power BI environment must be a premium/Fabric capacity and the account must have access to the workspace and datasets.
#>

# Setup TLS 12
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ---------- Check if PowerShell Modules are Installed ---------- #
#Install Az.Accounts if Needed
if (Get-Module -ListAvailable -Name "Az.Accounts") {
    Write-Host "Az.Accounts installed moving forward"
} else {
    Write-Host "Installing Az.Accounts"
    #Install Az.Accounts Module
    Install-Module -Name Az.Accounts -Scope CurrentUser -AllowClobber -Force
}

if (Get-Module -ListAvailable -Name "SqlServer") {
    Write-Host "SqlServer installed moving forward"
} else {
    Write-Host "Installing SqlServer"
    #Install SqlServer Module
    Install-Module -Name SqlServer -Scope CurrentUser -AllowClobber -Force
}
# ---------- Download Modules ------------- #
Write-Host "##[debug]Downloading FabricPS-PBIP module"

# Create a new directory in the current location
if(Test-Path -path ".\modules" -eq $false){
    New-Item -Name "modules" -Type Directory
}

@("https://raw.githubusercontent.com/kerski/fabric-dataops-patterns/development/Azure%20DevOps/Automated%20Testing%20Example/modules/FabricPS-PBIP.psm1",
  "https://raw.githubusercontent.com/kerski/fabric-dataops-patterns/development/Azure%20DevOps/Automated%20Testing%20Example/modules/FabricPS-PBIP.psd1") |% {
    Invoke-WebRequest -Uri $_ -OutFile ".\modules\$(Split-Path $_ -Leaf)"
}

Import-Module ".\modules\FabricPS-PBIP" -Force

# ---------- Validate Pipeline Variables ---------- #

# Get Environment Variables from the Pipeline
$opts = @{
    PowerBIURL = "https://api.powerbi.com"
    WorkspaceName = "${{ parameters.WORKSPACE_NAME }}"
    UserName = "${env:USERNAME_OR_CLIENTID}";
    Password = "${env:PASSWORD_OR_CLIENTSECRET}";
    TenantId = "${env:TENANT_ID}"
    IsServicePrincipal = $false
    DatasetIdsToTest = "${{ parameters.DATASET_IDS }}"
    BuildVersion = "${env:BUILD_SOURCEVERSION}";
    IsDebug = $True
}

# Check variables
if(!$opts.WorkspaceName){
    Write-Host "##vso[task.logissue type=error]No pipeline variable name WORKSPACE_NAME could be found."    
    exit 1
}
if(!$opts.UserName){
    Write-Host "##vso[task.logissue type=error]No pipeline variable name USERNAME_OR_CLIENTID could be found."    
    exit 1
}
if(!$opts.Password){
    Write-Host "##vso[task.logissue type=error]No pipeline variable name PASSWORD_OR_CLIENTSECRET could be found."    
    exit 1
}
if(!$opts.TenantId){
    Write-Host "##vso[task.logissue type=error]No pipeline variable name TENANT_ID could be found."    
    exit 1
}

# ---------- Setup Connection ---------- #
$secret = $opts.Password | ConvertTo-SecureString -AsPlainText -Force
$credentials = [System.Management.Automation.PSCredential]::new($opts.UserName,$secret)

# Check if service principal or username/password
$guidRegex = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'

if($opts.UserName -match $guidRegex){# Service principal used
    $opts.IsServicePrincipal = $true
    # Get Connection
    Set-FabricAuthToken -servicePrincipalId $opts.UserName -servicePrincipalSecret $opts.Password -tenantId $opts.TenantId -reset
}
else{ # Use account
    # Get Connection
    Set-FabricAuthToken -credential $credentials -tenantId $tenantId -reset                        

}# end service principal check

# Retrieve workspace name using filter capability
Try{
    $workspaceObj = Get-FabricWorkspace -workspaceName $opts.WorkspaceName
    $workspaceGuid = $workspaceObj.id
}Catch [System.Exception]{
    $errObj = ($_).ToString()
    Write-Host "##vso[task.logissue type=error]$($errObj)"
    exit 1
}#End Try

# Retrieve items from the workspace
$workspaceItems = Invoke-FabricAPIRequest -Uri "workspaces/$workspaceGuid/items" -Method Get
$datasets = $workspaceItems | Where-Object {$_.type -eq "SemanticModel"} 

if($opts.DatasetIdsToTest){ # Filter datasets to test specifically base 
    # Convert comma delimited string to array
    $idsToCheck = @($opts.DatasetIdsToTest -split ",")

    $datasetsToTest = @()

    foreach($id in $idsToCheck){
        $temp = $datasets | Where-Object {$_.Id -eq $id}
        if($temp){# only add to array if id matches
            $datasetsToTest+=$temp
        }
    }# end for each

    # Reassign 
    $datasets = $datasetsToTest
}


# Retrieve item.metadata.json files so we can map dataset names in the service
# with the name in the metdata files
$metadataObjs = @()
$metadataDS = @(Get-ChildItem -Path "*.Dataset/item.metadata.json" -Recurse)

foreach($m in $metadataDS){
    # Get Content on metdata
    $parentFolder = Split-Path -Path $m.FullName
    $content = Get-Content $m.FullName | ConvertFrom-Json
    $temp = @([pscustomobject]@{displayName=$content.displayName;FolderPath=$ParentFolder;})
    $metadataObjs += $temp
}#end for each

# ---------- Identify DAX Queries for Testing ---------- #
foreach($dataset in $datasets){
  Write-Host "##[debug]Identifying if any test files exist for $($dataset.displayName)"

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
                #Connect to XMLA EndPoint and run DAX Query
                Try {
                        # Get Token before each run of test
                        $authToken = Get-FabricAuthToken
                        $fabricHeaders = @{
                            'Content-Type' = "application/json"
                            'Authorization' = "Bearer {0}" -f $authToken
                        }

                        $requestUrl = "$($opts.PowerBIURL)/v1.0/myorg/groups/$($workspaceGuid)/datasets/$($dataset.Id)/executeQueries"
                        
                        #Retrieve Content of the test
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

                        #Check if Row Count is 0, no test results.
                        if ($requestResultJSON.results.tables.rows.Count -eq 0) {
                            $failureCount += 1
                            Write-Host "##vso[task.logissue type=error]Query in test file ""($testFile.FullName)"" returned no results."
                        }#end check of results

                        #Iterate through each row of the query results and check test results
                        $rowsToCheck = $requestResultJSON.results.tables.rows
                        foreach ($row in $rowsToCheck){

                                # Make sure schema exists for the row
                                $checkSchema = $row.PSObject.Members.name | Where-Object {$_ -eq "[TestName]" -or `
                                                                                        $_ -eq "[ExpectedValue]" -or `
                                                                                        $_ -eq "[ActualValue]" -or `
                                                                                        $_ -eq "[Passed]"}

                                # Expects Columns TestName, Expected, Actual Columns, Passed
                                if ($checkSchema.Count -ne 4) {
                                    $failureCount += 1
                                    Write-Host "##vso[task.logissue type=error]Query in test file ""$($test.FullName)"" did not have 4 columns (TestName, Expected, and Actual, Passed)."
                                }else{# Compute whether the test passed
                                    # Clear out values
                                    $testName = $null
                                    $expectedVal = $null
                                    $actualVal = $null
                                    $passed = $null
                                    # Assign values
                                    $testName = $row."[TestName]"
                                    $expectedVal = $row."[ExpectedValue]"
                                    $actualVal = $row."[ActualValue]"
                                    $passed = ($expectedVal -eq $actualVal)
                                    if (-not $passed) {
                                        $failureCount += 1
                                        Write-Host "##vso[task.logissue type=error]FAILED!: Test ""$($testName)"" for semantic model: $($datasetName). Expected: $($expectedVal) != $($actualVal)" }
                                    else{
                                        Write-Host "##[debug]""$($testName)"" passed. Expected: $($expectedVal) == $($actualVal)"
                                    }
                                }# end expected columns check
                        }#end foreach
                }Catch [System.Exception]{
                    $errObj = ($_).ToString()
                    Write-Host "##vso[task.logissue type=error]$($errObj)"
                    $failureCount +=1
            }# end try
            }# end for each test file
        }# end on test file counts
  }# end check metadata exists in this file structure for the dataset in the workspace
}# end foreach dataset

# Check failure count
if($failureCount -gt 0){
    exit 1 # Fail pipeline
}

