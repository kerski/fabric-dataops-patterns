# Functions using the Fabric API to programmatically deploy all supported items from the specified source stage to the specified target stage.

# For documentation, please see:
# https://learn.microsoft.com/en-us/rest/api/fabric/core/deployment-pipelines/deploy-stage-content
# https://learn.microsoft.com/en-us/rest/api/fabric/core/deployment-pipelines/list-deployment-pipelines
# https://learn.microsoft.com/en-us/rest/api/fabric/core/deployment-pipelines/get-deployment-pipeline-stages

function Set-FabricHeaders {
    param (
        [string] $FabricToken
    )
    return @{
        'Content-Type' = "application/json"
        'Authorization' = "Bearer {0}" -f $FabricToken
    }
}

function Get-DeploymentPipelineByName {
    param (
        [string] $DeploymentPipelineName,
        [hashtable] $FabricHeaders,
        [string] $BaseUrl
    )
    # Get deployment pipelines
    $deploymentPipelinesUrl = "{0}/deploymentPipelines" -f $BaseUrl
    $deploymentPipelines = (Invoke-RestMethod -Headers $FabricHeaders -Uri $deploymentPipelinesUrl -Method GET).value
    
    # Try to find the deployment pipeline by display name
    $deploymentPipeline = $deploymentPipelines | Where-Object {$_.DisplayName -eq $DeploymentPipelineName}
    
    # Verify the existence of the requested deployment pipeline
    if(!$deploymentPipeline) {
      Write-Host "##[debug]A deployment pipeline with the requested name: '$DeploymentPipelineName' was not found."
      return
    }
    
    return $deploymentPipeline
}

function Get-DeploymentPipelineStageByName {
    param (
        [string] $StageName,
        [string] $PipelineId,
        [hashtable] $FabricHeaders,
        [string] $BaseUrl
    )
    # Get deployment pipeline stages
    $deploymentPipelineStagesUrl = "{0}/deploymentPipelines/{1}/stages" -f $BaseUrl, $PipelineId
    $deploymentPipelineStages = (Invoke-RestMethod -Headers $FabricHeaders -Uri $deploymentPipelineStagesUrl -Method GET).value

    # Try to find the deployment pipeline stage by display name
    $deploymentPipelineStage = $deploymentPipelineStages | Where-Object {$_.DisplayName -eq $StageName}
    
    # Verify the existence of the requested deployment pipeline stage
    if(!$deploymentPipelineStage) {
      Write-Host "##[debug]A deployment pipeline stage with the requested name: '$StageName' was not found."
      return
    }
    
    return $deploymentPipelineStage
}

function Get-DeploymentPipelineStageByOrder {
    param (
        [int64] $StageOrder,
        [string] $PipelineId,
        [hashtable] $FabricHeaders,
        [string] $BaseUrl
    )
    # Get deployment pipeline stages
    $deploymentPipelineStagesUrl = "{0}/deploymentPipelines/{1}/stages" -f $BaseUrl, $PipelineId
    $deploymentPipelineStages = (Invoke-RestMethod -Headers $FabricHeaders -Uri $deploymentPipelineStagesUrl -Method GET).value

    # Try to find the deployment pipeline stage by display name
    $deploymentPipelineStage = $deploymentPipelineStages | Where-Object {$_.order -eq $StageOrder}
    
    # Verify the existence of the requested deployment pipeline stage
    if(!$deploymentPipelineStage) {
      Write-Host "##[debug]A deployment pipeline stage with the requested order: '$StageOrder' was not found."
      return
    }
    
    return $deploymentPipelineStage
}

function Publish-DeploymentPipelineStage {
    param (
        [string] $PipelineId,
        [pscustomobject] $SourceStage,
        [pscustomobject] $TargetStage,
        [hashtable] $FabricHeaders,
        [string] $BaseUrl
    )

    $success = $false

    $deployUrl = "{0}/deploymentPipelines/{1}/deploy" -f $BaseUrl, $PipelineId
    $deployBody = @{       
        sourceStageId = $SourceStage.id
        targetStageId = $TargetStage.id
        note = "Deploying all supported items from '$($SourceStage.displayName)' to '$($TargetStage.displayName)'"
    } | ConvertTo-Json
    
    $deployResponse = Invoke-WebRequest -Headers $FabricHeaders -Uri $deployUrl -Method POST -Body $deployBody
    $operationId = $deployResponse.Headers['x-ms-operation-id']
    if ($operationId -is [System.Array]) {
        $operationId = $operationId[0]  # Use the first value
    }
    $retryAfter = $deployResponse.Headers['Retry-After']
    if ($retryAfter -is [System.Array]) {
        $retryAfter = $retryAfter[0]  # Use the first value
    }
    Write-Host "##[debug]Long Running Operation ID: '$operationId' has been scheduled for deploying from $($sourceStage.displayName) to $($targetStage.displayName) with a retry-after time of '$retryAfter' seconds."
    
    # Get Long Running Operation Status
    Write-Host "##[debug]Polling long running operation ID '$($operationId)' has been started with a retry-after time of '$($retryAfter)' seconds."
    $getOperationState = "{0}/operations/{1}" -f $BaseUrl, $operationId
    do
    {
        $operationState = Invoke-RestMethod -Headers $fabricHeaders -Uri $getOperationState -Method GET
        Write-Host "##[debug]Deployment operation status: $($operationState.Status)"
        if ($operationState.Status -in @("NotStarted", "Running")) {
            Start-Sleep -Seconds $retryAfter
        }
    } while($operationState.Status -in @("NotStarted", "Running"))

    # Check if deployment failed
    if ($operationState.Status -eq "Failed") {
        Write-Host "##[debug]The deployment operation has been completed with failure. Error reponse: $($operationState.Error | ConvertTo-Json -Depth 10)"
    }
    else{
        # Get Long Running Operation Result
        Write-Host "##[debug]The deployment operation has been successfully completed. Getting LRO Result.."
        $operationResultUrl = "{0}/operations/{1}/result" -f $BaseUrl, $operationId
        $operationResult = Invoke-RestMethod -Headers $fabricHeaders -Uri $operationResultUrl -Method GET
        Write-Host "##[debug]Deployment operation result: `n$($operationResult | ConvertTo-Json -Depth 10)"
        $success = $true
    }

    return $success
}

function Get-ErrorResponse {
    param (
        [Parameter(Mandatory=$true)]
        [System.Exception] $Exception
    )
    # Relevant only for PowerShell Core
    $errorResponse = $_.ErrorDetails.Message

    if(!$errorResponse) {
        # This is needed to support Windows PowerShell
        if (!$Exception.Response) {
            return $Exception.Message
        }
        $result = $Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($result)
        $reader.BaseStream.Position = 0
        $reader.DiscardBufferedData()
        $errorResponse = $reader.ReadToEnd();
    }

    return $errorResponse
}
