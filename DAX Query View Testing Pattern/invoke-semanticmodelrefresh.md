---
external help file: Invoke-SemanticModelRefresh-help.xml
Module Name: Invoke-SemanticModelRefresh
online version:
schema: 2.0.0
---

# Invoke-SemanticModelRefresh

## SYNOPSIS
This module runs a synchronous refresh of a Power BI dataset/semantic model against the Power BI/Fabric workspace identified.

## SYNTAX

```
Invoke-SemanticModelRefresh [-WorkspaceId] <String> [-SemanticModelId] <String> [-TenantId] <String>
 [-Credential] <PSCredential> [-Environment] <PowerBIEnvironmentType> [-Timeout <Int64>] [-LogOutput <String>]
 [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
This module runs a synchronous refresh of a Power BI dataset/semantic model against the Power BI/Fabric workspace identified.
An enhanced refresh is issued to the dataset/semantic model and the status is checked until the refresh is completed or failed.

***Dependencies: A premium capacity (PPU, Premium, or Fabric) is required to refresh the dataset/semantic model.***

## EXAMPLES

### EXAMPLE 1
```
$RefreshResult = Invoke-SemanticModelRefresh -WorkspaceId $WorkspaceId `
                -SemanticModelId $SemanticModelId `
                -TenantId $TenantId `
                -Credential $Credential `
                -Environment $Environment `
                -LogOutput Host
```

## PARAMETERS

### -WorkspaceId
GUID representing workspace in the service

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: True
Position: 1
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -SemanticModelId
The GUID representing the semantic model in the service

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: True
Position: 2
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -TenantId
The GUID of the tenant where the Power BI workspace resides.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: True
Position: 3
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Credential
PSCredential

```yaml
Type: PSCredential
Parameter Sets: (All)
Aliases:

Required: True
Position: 4
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Environment
Microsoft.PowerBI.Common.Abstractions.PowerBIEnvironmentType type to identify which API host to use.

```yaml
Type: PowerBIEnvironmentType
Parameter Sets: (All)
Aliases:
Accepted values: Public, Germany, USGov, China, USGovHigh, USGovMil, Custom

Required: True
Position: 5
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Timeout
The number of minutes to wait for the refresh to complete. Default is 30 minutes.

```yaml
Type: Int64
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: 30
Accept pipeline input: False
Accept wildcard characters: False
```

### -LogOutput
Specifies where the log messages should be written.
Options are 'ADO' (Azure DevOps Pipeline) or Host.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: Host
Accept pipeline input: False
Accept wildcard characters: False
```

## OUTPUTS

Refresh status as defined is MS Docs: https://learn.microsoft.com/en-us/rest/api/power-bi/datasets/get-refresh-history-in-group#refresh

## RELATED LINKS

- [DAX Query View Testing Pattern](automated-testing-example.md)
- [Automating DAX Query View Testing Pattern with Azure DevOps](automated-testing-example.md)