$script:messages = @()

#Install Powershell Module if Needed
if (Get-Module -ListAvailable -Name "MicrosoftPowerBIMgmt") {
    #Write-Host -ForegroundColor Cyan "MicrosoftPowerBIMgmt already installed"
  } else {
    Install-Module -Name MicrosoftPowerBIMgmt -Scope CurrentUser -AllowClobber -Force
  }

  Import-Module -Name MicrosoftPowerBIMgmt

<#
    .SYNOPSIS
    This module runs a synchronous refresh of a Power BI dataset/semantic model against the Power BI/Fabric workspace identified.

    .DESCRIPTION
    This module runs a synchronous refresh of a Power BI dataset/semantic model against the Power BI/Fabric workspace identified.
    An enhanced refresh is issued to the dataset/semantic model and the status is checked until the refresh is completed or failed.
    A premium capacity (PPU, Premium, or Fabric) is required to refresh the dataset/semantic model.
    .PARAMETER WorkspaceId
    GUID representing workspace in the service

    .PARAMETER SemanticModelId
    The GUID representing the semantic model in the service

    .PARAMETER TenantId
    The GUID of the tenant where the Power BI workspace resides.

    .PARAMETER Credential
    PSCredential

    .PARAMETER Environment
    Microsoft.PowerBI.Common.Abstractions.PowerBIEnvironmentType type to identify which API host to use.

    .PARAMETER Timeout
    The number of minutes to wait for the refresh to complete. Default is 30 minutes.

    .PARAMETER RefreshType
    Refresh type to use. Refresh type as defined in MS Docs: https://learn.microsoft.com/en-us/rest/api/power-bi/datasets/refresh-dataset#datasetrefreshtype

    .PARAMETER ApplyRefreshPolicy
    Apply refresh policy as defined in MS Docs: https://learn.microsoft.com/en-us/analysis-services/tmsl/refresh-command-tmsl?view=asallproducts-allversions#optional-parameters

    .PARAMETER LogOutput
    Specifies where the log messages should be written. Options are 'ADO' (Azure DevOps Pipeline) or Host.

    .OUTPUTS
    Refresh status as defined is MS Docs: https://learn.microsoft.com/en-us/rest/api/power-bi/datasets/get-refresh-history-in-group#refresh

    .EXAMPLE
    $RefreshResult = Invoke-SemanticModelRefresh -WorkspaceId $WorkspaceId `
                    -SemanticModelId $SemanticModelId `
                    -TenantId $TenantId `
                    -Credential $Credential `
                    -Environment $Environment `
                    -LogOutput Host
#>
Function Invoke-SemanticModelRefresh {
    [CmdletBinding()]
    [OutputType([String])]
    Param(
        [Parameter(Position = 0, Mandatory = $true)][String]$WorkspaceId,
        [Parameter(Position = 1, Mandatory = $true)][String]$SemanticModelId,
        [Parameter(Position = 2, Mandatory = $true)][String]$TenantId,
        [Parameter(Position = 3, Mandatory = $true)][PSCredential]$Credential,
        [Parameter(Position = 4, Mandatory = $true)][Microsoft.PowerBI.Common.Abstractions.PowerBIEnvironmentType]$Environment,
        [Parameter(Mandatory = $false)][ValidateSet('automatic', 'full', 'clearValues', 'calculate')]$RefreshType = 'full',
        [Parameter(Mandatory = $false)][ValidateSet('true', 'false')]$ApplyRefreshPolicy = 'true',
        [Parameter(Mandatory = $false)][Int64]$Timeout = 30,
        [Parameter(Mandatory = $false)]
        [ValidateSet('ADO','Host')] # Override
        [string]$LogOutput = 'Host'
    )
    Process {
        # Setup TLS 12
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        Try {
            # Map to correct API Prefix
            $apiPrefix = "https://api.powerbi.com"
            switch($Environment){
                "Public" {$apiPrefix = "https://api.powerbi.com"}
                "Germany" {$apiPrefix = "https://api.powerbi.de"}
                "China" {$apiPrefix = "https://api.powerbi.cn"}
                "USGov" {$apiPrefix = "https://api.powerbigov.us"}
                "USGovHigh" {$apiPrefix = "https://api.high.powerbigov.us"}
                "USGovDoD" {$apiPrefix = "https://api.mil.powerbi.us"}
                Default {$apiPrefix = "https://api.powerbi.com"}
            }

            # Check if service principal or username/password
            $guidRegex = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
            $isServicePrincipal = $false

            if($Credential.UserName -match $guidRegex){# Service principal used
                $isServicePrincipal = $true
            }

            Write-ToLog -Message "Checking if Service Principal: $($isServicePrincipal)" `
            -LogType "Debug" `
            -LogOutput $LogOutput

            # Connect to Power BI
            if($isServicePrincipal){
                $connectionStatus = Connect-PowerBIServiceAccount -ServicePrincipal `
                                                                  -Credential $Credential `
                                                                  -Environment $Environment `
                                                                  -TenantId $TenantId
            }else{
                $connectionStatus = Connect-PowerBIServiceAccount -Credential $Credential `
                                                                  -Environment $Environment
            }

            # Check if connected
            if(!$connectionStatus){
                throw "Unable to authenticate to Fabric Service"
            }

            # Include Bearer prefix
            $token = Get-PowerBIAccessToken -AsString
            $headers = @{
                'Content-Type'  = "application/json"
                'Authorization' = $token
            }
            # Setup Refresh Endpoint
            $refreshUrl = "$($apiPrefix)/v1.0/myorg/groups/$($WorkspaceId)/datasets/$($SemanticModelId)/refreshes"
            # Write to log that we are attempting to refresh
            Write-ToLog -Message "Refreshing via URL: $($refreshUrl)" `
            -LogType "Debug" `
            -LogOutput $LogOutput

            # Issue Data Refresh with type full to get enhanced refresh
            $result = Invoke-WebRequest -Uri "$($refreshUrl)" -Method Post -Headers $headers -Body "{ `"type`": `"$RefreshType`",`"commitMode`": `"transactional`", `"applyRefreshPolicy`": `"$ApplyRefreshPolicy`", `"notifyOption`": `"NoNotification`"}" | Select-Object headers
            # Get Request ID
            $requestId = $result.Headers.'x-ms-request-id'
            # Add request id to url to get enhanced refresh status
            $refreshResultUrl = "$($refreshUrl)/$($requestId)"
            #Check for Refresh to Complete
            Start-Sleep -Seconds 10 #wait ten seconds before checking refresh first time
            $checkRefresh = 1

            $refreshStatus = "Failed"
            Do
            {
             $refreshResult = Invoke-PowerBIRestMethod -Url $refreshResultUrl -Method Get | ConvertFrom-JSON
             $refreshStatus = $refreshResult.status
             # Check date timestamp and verify no issue with top 1 being old
             $timeSinceRequest = New-Timespan -Start $refreshResult.startTime -End (Get-Date)
             if($timeSinceRequest.Minutes -gt $Timeout)
             {
                $checkRefresh = 1
             }# Check status.  Not Unknown means in progress
             elseif($refreshResult.status -eq "Completed")
             {
                $checkRefresh = 0
                Write-ToLog -Message "Refreshing Request ID: $($requestId) has Completed " `
                    -LogType "Completed" `
                    -LogOutput $LogOutput
             }
             elseif($refreshResult.status -eq "Failed")
             {
                $checkRefresh = 0
                Write-ToLog -Message "Refreshing Request ID: $($requestId) has FAILED" `
                    -LogType "Error" `
                    -LogOutput $LogOutput
             }
             elseif($refreshResult.status -ne "Unknown")
             {
                $checkRefresh = 0
                Write-ToLog -Message "Refreshing Request ID: $($requestId) is In Progress " `
                    -LogType "In Progress" `
                    -LogOutput $LogOutput
             }
             else #In Progress check, PBI uses Unknown for status
             {
                $checkRefresh = 1
                Write-ToLog -Message "Refreshing Request ID: $($requestId) is In Progress " `
                    -LogType "In Progress" `
                    -LogOutput $LogOutput

                Start-Sleep -Seconds 10 # Sleep wait seconds before running again
             }
            } While ($checkRefresh -eq 1)

            # Handle failure in ADO
            if($LogOutput -eq "ADO" -and $refreshStatus -eq "Failed"){
                Write-ToLog -Message "Failed to refresh with Request ID: $($requestId)" `
                    -LogType "Failure" `
                    -LogOutput $LogOutput
                exit 1
            }

            return $refreshStatus
        }Catch [System.Exception]{
          $errObj = ($_).ToString()
          Write-ToLog -Message "Refreshing Request ID: $($requestId) Failed. Message: $($errObj) " `
          -LogType "Error" `
          -LogOutput $LogOutput
        }#End Try

        return "Failed"
}#End Process
}#End Function
function Write-ToLog {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [Parameter(Mandatory = $false)]
        [ValidateSet('Debug','Warning','Error','Passed','Failed','Failure','Success','In Progress','Completed')]
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
            'Failed' { $prefix = "##vso[task.complete result=Failed;]"}
            'Completed' { $prefix = "##vso[task.complete result=Succeeded;]"}
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
            'Failed' { $color = "Red"}
            'Success' { $color = "Green"}
            'Completed' { $color = "Green"}
            'Debug' { $color = "Magenta"}
            'In Progress' { $color = "Magenta"}
        }
        Write-Host -ForegroundColor $color $Message
    }
} #end Write-ToLog

Export-ModuleMember -Function Invoke-SemanticModelRefresh