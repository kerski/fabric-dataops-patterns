<#
    Author: John Kerski

    .DESCRIPTION: This pipeline code run through the DAX Query View files that end with .Tests
    or .Test and output the results.

    Dependencies:  PowerShell modules Az.Accounts and SqlServer version 22.0 is required.

    Power BI environment must be a premium/Fabric capacity and the account must have access to the workspace and datasets/semantic models.
#>

# Setup TLS 12
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ---------- Check if PowerShell Modules are Installed ---------- #

#Install Az.Accounts if Needed
if (Get-Module -ListAvailable -Name "Az.Accounts") {
    Write-Host "##[debug]Az.Accounts installed moving forward"
} else {
    Write-Host "##[debug]Installing Az.Accounts"
    #Install Az.Accounts Module
    Install-Module -Name Az.Accounts -Scope CurrentUser -AllowClobber -Force
}

# ---------- Validate Pipeline Variables ---------- #

# Get Environment Variables from the Pipeline
$opts = @{
    FabricApiUrl = "https://api.fabric.microsoft.com"
    PowerBiUrl = "https://api.powerbi.com"
    XmlaPrefix = "powerbi://api.powerbi.com/v1.0/myorg/"
    WorkspaceName = "${env:WORKSPACE_NAME}"
    UserName = "${env:USERNAME_OR_CLIENTID}";
    Password = "${env:PASSWORD_OR_CLIENTSECRET}";
    TenantId = "${env:TENANT_ID}";
    IsServicePrincipal = $false;
    # Get new pbip changes
    PbiChanges = git diff --name-only --relative --diff-filter AMR HEAD^ HEAD '*.Dataset/*' '*.Report/*';
    BuildVersion = "${env:BUILD_SOURCEVERSION}";
}# Check variables
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

$conn = $null
if($opts.UserName -match $guidRegex){# Service principal used
    $opts.IsServicePrincipal = $true
    # Get Connection
    $conn = Connect-AzAccount -Credential $credentials -ServicePrincipal -Tenant $opts.TenantId
}
else{ # Use account
    # Get Connection
    $conn = Connect-AzAccount -Credential $credentials
}# end service principal check

# Get Authentication information
$connectionInfo = Get-AzAccessToken -ResourceUrl $opts.FabricApiUrl
$fabricToken = $connectionInfo.Token
$opts.TenantId = $connectionInfo.TenantId

if(!$fabricToken)
{
    Write-Error "Unable to access token."
    exit 1
}

$fabricHeaders = @{
    'Content-Type' = "application/json"
    'Authorization' = "Bearer {0}" -f $fabricToken
}   

# Retrieve workspace name using filter capability
$workspaceUrl =  "$($opts.PowerBiUrl)/v1.0/myorg/groups?`$filter=name eq '$($opts.WorkspaceName)' and state ne 'Deleted'"
$workspaceResult = Invoke-WebRequest -Headers $fabricHeaders -Uri $workspaceUrl -Method GET
$workspaceObj = $workspaceResult | ConvertFrom-Json

# Check if you can access the workspace or it exists
if($workspaceObj.value.count -eq 0){
    Write-Host "##vso[task.logissue type=error]Unable to locate workspace with name: $($opts.WorkspaceName)"
    exit 1
}
$workspaceGuid = $workspaceObj.value[0].id

# Retrieve datsaets for the workspace
$datasetsUrl = "$($opts.PowerBIURL)/v1.0/myorg/groups/$($workspaceGuid)/datasets"
$datasetsResult = Invoke-WebRequest -Headers $fabricHeaders -Uri $datasetsUrl -Method GET
$datasetsObj = $datasetsResult | ConvertFrom-Json

## TODO: Discuss if we should refresh for the proof of concept

# ---------- Identity DAX Queries for Testing ---------- #

# Identify the DAX Queries that have a .Tests or .Test
$testFiles = @(Get-ChildItem -Path "*.Dataset/DaxQueries" -Recurse | Where-Object {$_ -like "*.Tests.dax" -or $_ -like "*.Test.dax"})

if($testFiles.Count -eq 0){
    Write-Host "##vso[task.logissue type=warning]Unable to locate DAX files in this repository. No tests will be conducted."
}

# Regex to get semantic model name
# Note: This assumes the file name has not been changed previously
$pattern = "(?<=\\)([^\\]+)(?=\.Dataset)"
$failureCount = 0
# Execute Tests
foreach($testFile in $testFiles){
    $datasetName = $testFile.FullName | Select-String -Pattern $pattern -AllMatches | ForEach-Object { $_.Matches } | ForEach-Object { $_.Value }

    Write-Host "--------"
    Write-Host "##[debug]Running ""$($testFile.FullName)"" for semantic model: $datasetName"

    if($datasetName){
        #Connect to XMLA EndPoint and run DAX Query
        Try {
                #Retrieve dataset id
                $datasetToTest = $datasetsObj.value | Where-Object {$_.name -eq $datasetName}

                if(!$datasetToTest){
                    Write-Host "##vso[task.logissue type=error]Unable to locate Dataset named ""$($datasetName)"" in $($opts.WorkspaceName)"
                }
                else{# Found datset id, now execute queries
                    $requestUrl = "$($opts.PowerBIURL)/v1.0/myorg/groups/$($workspaceGuid)/datasets/$($datasetToTest.Id)/executeQueries"
                    
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
                        Write-Host "##vso[task.logissue type=error]Query in test file ""($testFile.FullName)"" returned no results."
                    }# end check of results

                    # Iterate through each row of the query results and check test results
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
                        }# end foreach
                }# end datset id check
            }Catch [System.Exception]{
                $errObj = ($_).ToString()
                Write-Host "##vso[task.logissue type=error]$($errObj)"
                $failureCount +=1
            }#End Try
    }else{
        Write-Host "##vso[task.logissue type=error]Unable to identify semantic model in file path: $($testFile.Name)"
    }
}# end foreach test file

if($failureCount -gt 0){
    exit 1 # Fail pipeline
}
