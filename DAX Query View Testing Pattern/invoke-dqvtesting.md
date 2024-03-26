# Invoke-DQVTesting

## SYNOPSIS
This module runs through the DAX Query View files that end with .Tests or .Test and output the results. 
This is based on following the DAX Query View Testing Pattern: https://github.com/kerski/fabric-dataops-patterns/blob/main/DAX%20Query%20View%20Testing%20Pattern/dax-query-view-testing-pattern.md

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
Run tests for all datasets/semantic models in the workspace and log output using Azure DevOps' logging commands.
Invoke-DQVTesting -WorkspaceName "WORKSPACE_NAME" `
                    -Credential $userCredentials `
                    -TenantId "TENANT_ID" `
                    -LogOutput "ADO"
```

### EXAMPLE 2
```
Run tests for specific datasets/semantic models in the workspace and log output using Azure DevOps' logging commands.
Invoke-DQVTesting -WorkspaceName "WORKSPACE_NAME" `
                    -Credential $userCredentials `
                    -TenantId "TENANT_ID" `
                    -DatasetId @("DATASET GUID1","DATASET GUID2") `
                    -LogOutput "ADO"
```

### EXAMPLE 3
```
Run tests for specific datasets/semantic models in the workspace and return output in an array of objects (table).
Invoke-DQVTesting -WorkspaceName "WORKSPACE_NAME" `
                    -Credential $userCredentials `
                    -TenantId "TENANT_ID" `
                    -DatasetId @("DATASET GUID1","DATASET GUID2") `
                    -LogOutput "Table"
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
Specifies where the log messages should be written.
Options are 'ADO' (Azure DevOps Pipeline), 'Host', or 'Table'.

When ADO is chosen:
- Any warning will be logged as an warning in the pipeline. 
An example of a warning would be
if a dataset/semantic model has no tests to conduct.
- Any failed tests will be logged as an error in the pipeline.
- Successfully tests will be logged as a debug in the pipeline.
- If at least one failed test occurs, a failure is logged in the pipeline.

When Host is chosen, all output is written via the Write-Output command.

When Table is chosen:
- An Array containing objects with the following properties:
    - message (String): The description of the event.
    - logType (String): This is either Debug, Warning, Error, or Failure.
    - isTestResult (Boolean): This indicates if the event was a test or not. 
This is helpful for filtering results.

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

## OUTPUTS

[See LogOutput](#logoutput)

## NOTES
Author: John Kerski
Dependencies:  PowerShell modules Az.Accounts is required.
Power BI environment must be a Premium or Fabric capacity and the account must have access to the workspace and datasets.
This script depends on FabricPS-PBIP which resides in Microsoft's Analysis Services GitHub site.

## RELATED LINKS

- [DAX Query View Testing Pattern](automated-testing-example.md)
- [Automating DAX Query View Testing Pattern with Azure DevOps](automated-testing-example.md)