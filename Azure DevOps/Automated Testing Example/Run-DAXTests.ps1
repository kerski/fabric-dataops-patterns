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
    IsDebug = $True
}

if($opts.IsDebug -eq $True){
    Write-Host $opts
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
$workspaceResult = Invoke-WebRequest -Headers $fabricHeaders -Uri $workspaceUrl -Method GET -Verbose
$workspaceObj = $workspaceResult | ConvertFrom-Json

# Check if you can access the workspace or it exists
if($workspaceObj.value.count -eq 0){
    Write-Host "##vso[task.logissue type=error]Unable to locate workspace with name: $($opts.WorkspaceName)"
    exit 1
}

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
                $result = $null

                if($opts.IsServicePrincipal){ # use service principal
                    $result = Invoke-ASCmd -Server "$($opts.XmlaPrefix)$($opts.WorkspaceName)" `
                    -Database $datasetName `
                    -InputFile $testFile.FullName `
                    -Credential $credentials `
                    -TenantId $opts.TenantId -ServicePrincipal
                }
                else{ # Issue XMLA request using username and password
                    $result = Invoke-ASCmd -Server "$($opts.XmlaPrefix)$($opts.WorkspaceName)" `
                    -Database $datasetName `
                    -InputFile $testFile.FullName `
                    -Credential $credentials `
                    -TenantId $opts.TenantId
                }# end check for service principal setting

                #Remove unicode chars for brackets and spaces from XML node names
                $result = $result -replace '_x[0-9A-z]{4}_', '';

                #Load into XML and return
                [System.Xml.XmlDocument]$xmlResult = New-Object System.Xml.XmlDocument
                $xmlResult.LoadXml($result)

                #Get Node List
                [System.Xml.XmlNodeList]$rows = $xmlResult.GetElementsByTagName("row")

                #Check if Row Count is 0, no test results.
                if ($rows.Count -eq 0) {
                    $failureCount += 1
                    Write-Host "##vso[task.logissue type=error]Query in test file ""($testFile.FullName)"" returned no results."
                }#end check of results

                #Iterate through each row of the query results and check test results
                foreach ($row in $rows){
                    #Expects Columns TestName, Expected, Actual Columns, Passed
                    if ($row.ChildNodes.Count -ne 4) {
                        $failureCount += 1
                        Write-Host "##vso[task.logissue type=error]Query in test file ""$($test.FullName)"" returned no results that did not have 4 columns (TestName, Expected, and Actual, Passed)."
                    }else{
                        #Extract Values
                        $testName = $row.ChildNodes[0].InnerText
                        $expectedVal = $row.ChildNodes[1].InnerText
                        $actualVal = $row.ChildNodes[2].InnerText
                        #Compute whether the test passed
                        $passed = ($expectedVal -eq $actualVal) -and ($expectedVal -and $actualVal)
                       if (-not $passed) {
                            $failureCount += 1
                            Write-Host "##vso[task.logissue type=error]FAILED!: Test ""$($testName)"" for semantic model: $($datasetName). Expected: $($expectedVal) != $($actualVal)"          }
                        else{
                            Write-Host "##[debug]$($testName) passed. Expected: $($expectedVal) == $($actualVal)"
                        }
                    }# end expected columns check
                }#end foreach

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
