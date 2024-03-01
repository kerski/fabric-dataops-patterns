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

# ---------- Validate Pipeline Variables ---------- #

# Get Environment Variables from the Pipeline
$Opts = @{
    FabricAPIURL = "https://api.fabric.microsoft.com"
    PowerBIURL = "https://api.powerbi.com"
    XMLAPrefix = "powerbi://api.powerbi.com/v1.0/myorg/"
    WorkspaceName = "${env:WORKSPACE_NAME}"
    UserName = "${env:USERNAME_OR_CLIENTID}";
    Password = "${env:PASSWORD_OR_CLIENTSECRET}";
    IsServicePrincipal = $false;
    # Get new pbip changes
    PbiChanges = git diff --name-only --relative --diff-filter AMR HEAD^ HEAD '*.Dataset/*' '*.Report/*';
    BuildVersion = "${env:BUILD_SOURCEVERSION}";
    IsDebug = $True
}

Write-Host $Opts

# Check variables
if(!$Opts.WorkspaceName){
    Write-Host "##vso[task.logissue type=error]No pipeline variable name WORKSPACE_NAME could be found."    
    exit 1
}
if(!$Opts.UserName){
    Write-Host "##vso[task.logissue type=error]No pipeline variable name USER_NAME could be found."    
    exit 1
}
if(!$Opts.Password){
    Write-Host "##vso[task.logissue type=error]No pipeline variable name PASSWORD could be found."    
    exit 1
}

# ---------- Setup Connection ---------- #
$Secret = $Opts.Password | ConvertTo-SecureString -AsPlainText -Force
$Credentials = [System.Management.Automation.PSCredential]::new($Opts.UserName,$Secret)

# Check if service principal or username/password
$GuidRegex = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'

$Conn = $null
if($Opts.UserName -match $GuidRegex){# Service principal used
    $Opts.IsServicePrincipal = $true
    # Get Connection
    $Conn = Connect-AzAccount -Credential $Credentials -ServicePrincipal
}
else{ # Use account
    # Get Connection
    $Conn = Connect-AzAccount -Credential $Credentials
}# end service principal check

# Get Authentication information
$ConnectionInfo = Get-AzAccessToken -ResourceUrl $Opts.FabricAPIURL
$FabricToken = $ConnectionInfo.Token
$Opts.TenantId = $ConnectionInfo.TenantId

if(!$FabricToken)
{
    Write-Error "Unable to access token."
    return
}

$FabricHeaders = @{
    'Content-Type' = "application/json"
    'Authorization' = "Bearer {0}" -f $FabricToken
}   

# Retrieve workspace name using filter capability
$WorkspaceURL =  "$($Opts.PowerBIURL)/v1.0/myorg/groups?`$filter=name eq '$($Opts.WorkspaceName)' and state ne 'Deleted'"
$WorkspaceResult = Invoke-WebRequest -Headers $FabricHeaders -Uri $WorkspaceURL -Method GET -Verbose
$WorkspaceObj = $WorkspaceResult | ConvertFrom-Json

# Check if you can access the workspace or it exists
if($WorkspaceObj.value.count -eq 0){
    Write-Host "##vso[task.logissue type=error]Unable to locate workspace with name: $($Opts.WorkspaceName)"
    exit 1
}

## TODO: Discuss if we should refresh for the proof of concept

# ---------- Identity DAX Queries for Testing ---------- #

# Identify the DAX Queries that have a .Tests or .Test
$TestFiles = @(Get-ChildItem -Path "*.Dataset/DaxQueries" -Recurse | Where-Object {$_ -like "*.Tests.dax" -or $_ -like "*.Test.dax"})

if($TestFiles.Count -eq 0){
    Write-Host "##vso[task.logissue type=warning]Unable to locate DAX files in this repository. No tests will be conducted."
}

# Regex to get semantic model name
# Note: This assumes the file name has not been changed previously
$Pattern = "(?<=\\)([^\\]+)(?=\.Dataset)"
$FailureCount = 0
# Execute Tests
foreach($TestFile in $TestFiles){
    $DatasetName = $TestFile.FullName | Select-String -Pattern $Pattern -AllMatches | ForEach-Object { $_.Matches } | ForEach-Object { $_.Value }

    Write-Host "--------"
    Write-Host "##[debug]Running $($TestFile.FullName) for dataset $DatasetName"

    if($DatasetName){
        #Connect to XMLA EndPoint and run DAX Query
        Try {
                $Result = $null

                if($Opts.IsServicePrincipal){ # use service principal
                    $Result = Invoke-ASCmd -Server "$($Opts.XMLAPrefix)$($WorkspaceName)" `
                    -Database $DatasetName `
                    -InputFile $TestFile.FullName `
                    -Credential $Credentials `
                    -TenantId $Opts.TenantId   
                    -ServicePrincipal
                }
                else{ # Issue XMLA request using username and password
                    $Result = Invoke-ASCmd -Server "$($Opts.XMLAPrefix)$($Opts.WorkspaceName)" `
                    -Database $DatasetName `
                    -InputFile $TestFile.FullName `
                    -Credential $Credentials `
                    -TenantId $Opts.TenantId
                }# end check for service principal setting

                #Remove unicode chars for brackets and spaces from XML node names
                $Result = $Result -replace '_x[0-9A-z]{4}_', '';

                #Load into XML and return
                [System.Xml.XmlDocument]$XmlResult = New-Object System.Xml.XmlDocument
                $XmlResult.LoadXml($Result)

                #Get Node List
                [System.Xml.XmlNodeList]$Rows = $XmlResult.GetElementsByTagName("row")

                #Check if Row Count is 0, no test results.
                if ($Rows.Count -eq 0) {
                    $FailureCount += 1
                    Write-Host "##vso[task.logissue type=error]Query in test file $($TestFile.FullName) returned no results."
                }#end check of results

                #Iterate through each row of the query results and check test results
                foreach ($Row in $Rows){
                    #Expects Columns TestName, Expected, Actual Columns, Passed
                    if ($Row.ChildNodes.Count -ne 4) {
                        $FailureCount += 1
                        Write-Host "##vso[task.logissue type=error]Query in test file $($Test.FullName) returned no results that did not have 4 columns (TestName, Expected, and Actual, Passed)."
                    }else{
                        #Extract Values
                        $TestName = $Row.ChildNodes[0].InnerText
                        $ExpectedVal = $Row.ChildNodes[1].InnerText
                        $ActualVal = $Row.ChildNodes[2].InnerText
                        #Compute whether the test passed
                        $Passed = ($ExpectedVal -eq $ActualVal) -and ($ExpectedVal -and $ActualVal)
                       if (-not $Passed) {
                            $FailureCount += 1
                            Write-Host "##vso[task.logissue type=error]FAILED!: Test $($TestName) for $($DatasetName). Expected: $($ExpectedVal) != $($ActualVal)"          }
                        else{
                            Write-Host "##[debug]$($TestName) passed. Expected: $($ExpectedVal) == $($ActualVal)"
                        }
                    }# end expected columns check
                }#end foreach

            }Catch [System.Exception]{
                $ErrObj = ($_).ToString()
                Write-Host "##vso[task.logissue type=error]$($ErrObj)"
            }#End Try
    }else{
        Write-Host "##vso[task.logissue type=error]Unable to identify Dataset Name in file path: $($TestFile.Name)"
    }
}# end foreach test file

if($FailureCount -gt 0){
    exit 1 # Fail pipeline
}