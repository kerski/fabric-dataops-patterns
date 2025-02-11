# ---------- Check if PowerShell Modules are Installed ---------- #
# Install Az.Accounts if Needed
if (!(Get-Module -ListAvailable -Name "Az.Accounts")) {
    #Install Az.Accounts Module
    Install-Module -Name Az.Accounts -Scope CurrentUser -AllowClobber -Force
}

# Install Invoke-DQVTesting
if (!(Get-Module -ListAvailable -Name "Invoke-DQVTesting")) {
    #Install Invoke-DQVTesting Module
    Install-Module -Name Invoke-DQVTesting -Scope CurrentUser -AllowClobber -Force
}     

# Install Invoke-SemanticModelRefresh
if (!(Get-Module -ListAvailable -Name "Invoke-SemanticModelRefresh")) {
    Install-Module -Name Invoke-SemanticModelRefresh -Scope CurrentUser -AllowClobber -Force
}      
        
# Create a new directory in the current location
if ((Test-Path -path ".\.nuget\custom_modules") -eq $false) {
    New-Item -Name ".nuget\custom_modules" -Type Directory
}

# For each url download and install in module folder
@("https://raw.githubusercontent.com/microsoft/Analysis-Services/master/pbidevmode/fabricps-pbip/FabricPS-PBIP.psm1",
    "https://raw.githubusercontent.com/microsoft/Analysis-Services/master/pbidevmode/fabricps-pbip/FabricPS-PBIP.psd1") | ForEach-Object {
    Invoke-WebRequest -Uri $_ -OutFile ".\.nuget\custom_modules\$(Split-Path $_ -Leaf)"
}



# ---------- Import PowerShell Modules ---------- #
# Import FabricPS-PBIP
Import-Module ".\.nuget\custom_modules\FabricPS-PBIP" -Force

# Import module to support deployment pipeline functions
Import-Module ".\DAX Query View Testing Pattern\PipelineScripts\custom_modules\DeploymentPipelines" -Force



# ---------- Setup Credentials ---------- #
$secret = ${env:PASSWORD_OR_CLIENTSECRET} | ConvertTo-SecureString -AsPlainText -Force
$credential = [System.Management.Automation.PSCredential]::new(${env:USERNAME_OR_CLIENTID}, $secret)  

# Check if service principal or username/password
$guidRegex = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
$isServicePrincipal = $false

if ($credential.UserName -match $guidRegex) {
    # Service principal used
    $isServicePrincipal = $true
}

# Convert secure string to plain text to use in connection strings
$secureStringPtr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($credential.Password)
$plainTextPwd = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($secureStringPtr)

# Set Fabric Connection
if ($isServicePrincipal) {
    Set-FabricAuthToken -servicePrincipalId $credential.UserName `
        -servicePrincipalSecret $plainTextPwd `
        -tenantId ${env:TENANT_ID} -reset
    $fabricToken = Get-FabricAuthToken
}
else {
    # User account
    Set-FabricAuthToken -credential $credential -tenantId ${env:TENANT_ID} -reset
    $fabricToken = Get-FabricAuthToken
}



# ---------- Identify Changes For Promotion ---------- #
$pbipSMChanges = @(git diff --name-only --relative --diff-filter=d HEAD~1..HEAD -- '*.Dataset/**' '*.SemanticModel/**')
$pbipSMChanges += @(git diff --name-only --relative --diff-filter=d HEAD~2..HEAD -- '*.Dataset/**' '*.SemanticModel/**')
$pbipSMChanges = $pbipSMChanges | Sort-Object -Unique
$pbipRptChanges = @(git diff --name-only --relative --diff-filter=d HEAD~1..HEAD -- '*.Report/**')
$pbipRptChanges += @(git diff --name-only --relative --diff-filter=d HEAD~2..HEAD -- '*.Report/**')
$pbipRptChanges = $pbipRptChanges | Sort-Object -Unique
        
# Detect if no changes
if ($null -eq $pbipSMChanges -and $null -eq $pbipRptChanges) {
    Write-Host "##[debug]No changes detected in the Semantic Model or Report folders. Exiting..."
    exit 0
}

# Get workspace Id
$workspaceObj = Get-FabricWorkspace -workspaceName "${env:WORKSPACE_NAME}"                    
$workspaceID = $workspaceObj.Id    



# ---------- Handle Semantic Models For Promotion ---------- #
# Identify Semantic Models changed
$sMPathsToPromote = @()
$filter = "*.pbism"

foreach ($change in $pbipSMChanges) {
    $parentFolder = Split-Path $change -Parent
    while ($null -ne $parentFolder -and !( Test-Path( Join-Path $parentFolder $filter))) {
        $parentFolder = Split-Path $parentFolder -Parent
    }
    $sMPathsToPromote += $parentFolder
}# end foreach

# Remove duplicates
$sMPathsToPromote = @([System.Collections.Generic.HashSet[string]]$sMPathsToPromote)     

# Setup promoted items array
$sMPromotedItems = @()

# Promote semantic models to workspace
foreach ($promotePath in $sMPathsToPromote) {
    Write-Host "##[debug]Promoting semantic model at $($promotePath) to workspace ${env:WORKSPACE_NAME}"
    $sMPromotedItems += Import-FabricItem -workspaceId $workspaceID -path $promotePath
}# end foreach  



# ---------- Promote Reports  ---------- #
# Retrieve all items in workspace
# Do this after semantic models have been promoted
$items = Invoke-FabricAPIRequest -Uri "workspaces/$($workspaceID)/items" -Method Get            

# Identify Reports changed
$rptPathsToPromote = @()
$filter = "*.pbir"

foreach ($change in $pbipRptChanges) {
    $parentFolder = Split-Path $change -Parent
    while ($null -ne $parentFolder -and !( Test-Path( Join-Path $parentFolder $filter))) {
        $parentFolder = Split-Path $parentFolder -Parent
    }
    $rptPathsToPromote += $parentFolder
}# end foreach

# Remove duplicates
$rptPathsToPromote = @([System.Collections.Generic.HashSet[string]]$rptPathsToPromote)            

# Setup promoted items array
$rptPromotedItems = @()        

# Promote reports to workspace
foreach ($promotePath in $rptPathsToPromote) {
    # Get report definition
    $def = Get-ChildItem -Path $promotePath -Recurse -Include "definition.pbir"
    $semanticModelPath = (Get-Content $def.FullName | ConvertFrom-Json).datasetReference.byPath

    # If byPath was null, we'll assume byConnection is set and skip
    if ($null -ne $semanticModelPath) {
        # Semantic Model path is relative to the report path, Join-Path can handle relative paths
        $pathToCheck = Join-Path $promotePath $semanticModelPath.path
        $metadataSM = Get-ChildItem -Path $pathToCheck -Recurse -Include "item.metadata.json", ".platform" | `
            Where-Object { (Split-Path -Path $_.FullName).EndsWith(".Dataset") -or (Split-Path -Path $_.FullName).EndsWith(".SemanticModel") }

        $semanticModelName = $null
        $semanticModel = $null
        # If file is there let's get the display name
        if ($null -ne $metadataSM) {
            $content = Get-Content $metadataSM.FullName | ConvertFrom-Json

            # Handle item.metadata.json
            if ($metadataSM.Name -eq 'item.metadata.json') {
                # prior to March 2024 release
                $semanticModelName = $content.displayName
            }
            else {
                $semanticModelName = $content.metadata.displayName
            } #end if
        }
        else {
            Write-Host "##vso[task.logissue type=error]Semantic Model definition not found in workspace."
        }

        # Get the semantic model id from items in the workspace
        $semanticModel = $items | Where-Object { $_.type -eq "SemanticModel" -and $_.displayName -eq $semanticModelName }   
              
        if (!$semanticModel) {
            Write-Host "##vso[task.logissue type=error]Semantic Model not found in workspace."
        }
        else {    
            # Import report with appropriate semantic model id
            Write-Host "##[debug]Promoting report at $($promotePath) to workspace ${env:WORKSPACE_NAME}"
            $promotedItem = Import-FabricItem -workspaceId $workspaceID -path $promotePath -itemProperties @{semanticmodelId = "$($semanticModel.id)" }
            $rptPromotedItems += $promotedItem          
        }
    }
    else {
        # Promote thin report that already has byConnection set
        Write-Host "##[debug]Promoting report at $($promotePath) to workspace ${env:WORKSPACE_NAME}"
        $promotedItem = Import-FabricItem -workspaceId $workspaceID -path $promotePath
        $rptPromotedItems += $promotedItem                    
    }
}# end foreach


# ---------- Run Refreshes and Tests ---------- #
$FailureCount = 0
# Run synchronous refresh for each semantic model
foreach ($promotedItem in $sMPromotedItems) {
    # Test refresh which validates functionality
    $RefreshResults = Invoke-SemanticModelRefresh -WorkspaceId $workspaceID `
        -SemanticModelId  $promotedItem.Id `
        -Credential $credential `
        -TenantId "${env:TENANT_ID}" `
        -Environment Public `
        -LogOutput "ADO"

    # Check if refresh results are null or not, if null then set the failure count to 1
    Write-Host "##[debug]Checking refresh results for promoted item $($promotedItem.displayName) to workspace ${env:WORKSPACE_NAME}"
    if ($null -eq $RefreshResults -or $RefreshResults[-1] -ne "Completed") {
        $FailureCount += 1
        Write-Host "##vso[task.logissue type=warning]Failed to refresh $($promotedItem.displayName); status was $($RefreshResults[-1]). Please resolve."
    }
    else {
            # Run tests for functionality and data accuracy
            $TestResults = Invoke-DQVTesting -WorkspaceName "${env:WORKSPACE_NAME}" `
                -Credential $credential `
                -TenantId "${env:TENANT_ID}" `
                -DatasetId $promotedItem.Id `
                -LogOutput "Table"

            # Check if test results are null or not, if null then set the failure count
            $testsFailed =  ($TestResults | Where-Object {$_.IsTestResult -eq "True" -and $_.LogType -eq "Failed"}).Count
            Write-Host "##[debug]Checking DAX query test results for promoted item $($promotedItem.displayName) to workspace ${env:WORKSPACE_NAME}"
            if ($null -eq $TestResults -or $TestResults[-1].LogType -ne "Success") {
                $FailureCount += $testsFailed
                Write-Host "##vso[task.logissue type=error]$($FailureCount) failed test(s). Please resolve."
                exit 1
            }
            else {
                $TestResults | Where-Object {$_.IsTestResult -eq "True"} | ForEach-Object {Write-Host "##[debug]$($_.Message)"}
            }
    } 
}# end foreach



# ---------- Deploy the source workspace's artifacts to the next stage ---------- #
try {
    $fabricHeaders = Set-FabricHeaders -FabricToken $fabricToken
    
    Write-Host "##[debug]Getting deployment pipeline by name: $($env:DEPLOYMENT_PIPELINE_NAME)"
    $deploymentPipeline = Get-DeploymentPipelineByName -DeploymentPipelineName $env:DEPLOYMENT_PIPELINE_NAME `
        -FabricHeaders $fabricHeaders `
        -BaseUrl $env:BASE_URL
    
    Write-Host "##[debug]Getting deployment pipeline SOURCE stage by name: $($env:SOURCE_STAGE_NAME)"
    $sourceStage = Get-DeploymentPipelineStageByName -StageName $env:SOURCE_STAGE_NAME `
    -PipelineId $deploymentPipeline.id `
    -FabricHeaders $fabricHeaders  `
    -BaseUrl $env:BASE_URL

    Write-Host "##[debug]Getting deployment pipeline TARGET stage by order: $($sourceStage.order + 1)"
    $targetStage = Get-DeploymentPipelineStageByOrder -StageOrder ($sourceStage.order + 1) `
    -PipelineId $deploymentPipeline.id `
    -FabricHeaders $fabricHeaders  `
    -BaseUrl $env:BASE_URL

    Write-Host "##[debug]Deploying all supported items from '$($sourceStage.displayName)' to '$($targetStage.displayName)"
    $success = Publish-DeploymentPipelineStage -PipelineId $deploymentPipeline.id `
        -SourceStage $sourceStage `
        -TargetStage $targetStage `
        -FabricHeaders $fabricHeaders  `
        -BaseUrl $env:BASE_URL
    if (!$success) {
        Write-Host "##vso[task.logissue type=error]Failed to deploy to the next stage in the deployment pipeline. Please resolve."
        exit 1
    }
}
catch {
    $errorResponse = Get-ErrorResponse -Exception $_.Exception
    Write-Host "##vso[task.logissue type=error]Failed to deploy to the next stage in the deployment pipeline. Error reponse: $errorResponse"
    exit 1
}
