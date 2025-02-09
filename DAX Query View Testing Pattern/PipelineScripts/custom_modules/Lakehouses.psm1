function Connect-Lakehouse {
    param (
        [string] $ClientId,
        [string] $ClientSecret,
        [string] $TenantId,
        [string] $OneLakeUrl
    )

    $env:AZCOPY_SPA_CLIENT_SECRET = $ClientSecret

    $onelakeUri = New-Object System.Uri("$OneLakeUrl" )
    $onelakeDomain = $onelakeUri.Host

    $loginResult = azcopy login --service-principal `
        --application-id $ClientId `
        --tenant-id $TenantId `
        --trusted-microsoft-suffixes="$($onelakeDomain)" `
        --output-type json | ConvertFrom-Json

    return $loginResult
}

function Get-LakehouseByName {
    param (
        [string] $LakehouseName,
        [string] $WorkspaceName,
        [hashtable] $FabricHeaders,
        [string] $BaseUrl
    )

    # Get the workspace id where the lakehouse resides
    $workspaceObj = Get-FabricWorkspace -workspaceName "$($WorkspaceName)"                    
    $workspaceID = $workspaceObj.Id

    # Get lakehouses in the workspace
    $workspaceLakehousesUrl = "{0}/workspaces/{1}/lakehouses" -f $BaseUrl, $workspaceID
    $workspaceLakehouses = (Invoke-RestMethod -Headers $FabricHeaders -Uri $workspaceLakehousesUrl -Method GET).value

    # Try to find the lakehouse by display name
    $workspaceLakehouse = $workspaceLakehouses | Where-Object {$_.displayName -eq $LakehouseName}
    
    # Verify the existence of the requested lakehouse
    if(!$workspaceLakehouse) {
      Write-Host "##[debug]A lakehouse with the requested name: '$LakehouseName' was not found."
      return
    }
    
    return $workspaceLakehouse
}

function Write-FileToLakehouse {
    param (
        [string] $FilePath,
        [string] $OneLakeUrl
    )

    $onelakeUri = New-Object System.Uri("$OneLakeUrl" )
    $onelakeDomain = $onelakeUri.Host

    $copyResults = azcopy copy $FilePath "$($OneLakeUrl)" --overwrite=true `
    --blob-type=Detect `
    --check-length=true `
    --put-md5 `
    --trusted-microsoft-suffixes="$($onelakeDomain)" `
    --output-type json | ConvertFrom-Json

    return $copyResults
}