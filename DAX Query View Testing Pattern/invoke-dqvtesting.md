---
external help file: Invoke-DQVTesting-help.xml
Module Name: Invoke-DQVTesting
online version:
schema: 2.0.0
---

# Invoke-DQVTesting

## SYNOPSIS
This module runs through the DAX Query View files that end with .Tests or .Test and output the results.  This is based on following the DAX Query View Testing Pattern: https://github.com/kerski/fabric-dataops-patterns/blob/main/DAX%20Query%20View%20Testing%20Pattern/dax-query-view-testing-pattern.md

## SYNTAX

```
Invoke-DQVTesting [-TenantId] <String> [-WorkspaceName] <String> [-Credential] <PSCredential>
 [[-DatasetId] <Array>] [[-LogOutput] <String>] [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
The provided PowerShell script facilitates Data Query View (DQV) testing for datasets within a Fabric workspace.

Tests should follow the DAX Query View Testing Pattern that returns a table with 4 column "TestName", "ExpectedValue", "ActualValue", "Passed".

For more information, please visit this link: https://github.com/kerski/fabric-dataops-patterns/blob/main/DAX%20Query%20View%20Testing%20Pattern/dax-query-view-testing-pattern.md

## EXAMPLES

### EXAMPLE 1
```
Run tests for all datasets/semantic models in the workspace
Invoke-DQVTesting -WorkspaceName "WORKSPACE_NAME" `
                    -Credential $userCredentials `
                    -TenantId "TENANT_ID" `
                    -LogOutput "ADO"
```

### EXAMPLE 2
```
Run tests for specific datasets/semantic models in the workspace
Invoke-DQVTesting -WorkspaceName "WORKSPACE_NAME" `
                    -Credential $userCredentials `
                    -TenantId "TENANT_ID" `
                    -DatasetId @("DATASET GUID1","DATASET GUID2") `
                    -LogOutput "ADO"
```

## PARAMETERS

### -TenantId
The ID of the tenant where the Power BI workspace resides.

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

### -WorkspaceName
The name of the Power BI workspace where the datasets are located.

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

### -Credential
A PSCredential object containing the credentials used for authentication.

```yaml
Type: PSCredential
Parameter Sets: (All)
Aliases:

Required: True
Position: 3
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -DatasetId
An optional array of dataset IDs to specify which datasets to test.
If not provided, all datasets will be tested.

```yaml
Type: Array
Parameter Sets: (All)
Aliases:

Required: False
Position: 4
Default value: @()
Accept pipeline input: False
Accept wildcard characters: False
```

### -LogOutput
Specifies where the log messages should be output.
Options are 'ADO' (Azure DevOps Pipeline), 'Host', or 'Table'.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 5
Default value: ADO
Accept pipeline input: False
Accept wildcard characters: False
```

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

## NOTES
Author: John Kerski
Dependencies:  PowerShell modules Az.Accounts is required.
Power BI environment must be a Premium or Fabric capacity and the account must have access to the workspace and datasets.
This script depends on FabricPS-PBIP which resides in Microsoft's Analysis Services GitHub site.

## RELATED LINKS
