# Invoke-DQVTesting

## SYNOPSIS
This module runs through the DAX Query View files that end with .Tests or .Test and output the results. 
This is based on following the DAX Query View Testing Pattern: https://github.com/kerski/fabric-dataops-patterns/blob/main/DAX%20Query%20View%20Testing%20Pattern/dax-query-view-testing-pattern.md

## SYNTAX

### Default (Default)
```
Invoke-DQVTesting [-Path <String>] [-TenantId <String>] [-WorkspaceName <String>] [-Credential <PSCredential>]
 [-DatasetId <Array>] [-LogOutput <String>] [-CI] [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

### Local
```
Invoke-DQVTesting [-Local] [-Path <String>] [-LogOutput <String>] [-ProgressAction <ActionPreference>]
 [<CommonParameters>]
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

### EXAMPLE 4
```
Run tests for specific datasets/semantic models in the workspace and in subdirectories with names that begin with 'Model'.
Output will use Azure DevOps' logging commands.
Invoke-DQVTesting -WorkspaceName "WORKSPACE_NAME" `
                    -Credential $userCredentials `
                    -TenantId "TENANT_ID" `
                    -DatasetId @("DATASET GUID1","DATASET GUID2") `
                    -LogOutput "ADO" `
                    -Path ".\Model*"
```

### EXAMPLE 5
```
Run tests for specific datasets/semantic models opened locally (via Power BI Desktop) and return output in an array of objects (table).
Invoke-DQVTesting -Local
```

### EXAMPLE 6
```
Run tests for specific datasets/semantic models opened locally (via Power BI Desktop) and execute tests only in subdirectories with names that begin with 'Model'.
Returns output in an array of objects (table).
Invoke-DQVTesting -Local -Path ".\Model*"
```

## PARAMETERS

### -Local
When this switch is used, this module will identify the Power BI files opened on your local machine (opened with Power BI Desktop) and run tests associated with the opened Power BI Files.
The purpose of this switch is to allow you to test locally before automated testing occurs in a Continous Integration pipeline.

When the Local parameter is used, TenantId, WorkspaceName, and Credential parameter is not required.

```yaml
Type: SwitchParameter
Parameter Sets: Local
Aliases:

Required: True
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -Path
Specifies paths to files containing tests.
The value is a path\file name or name pattern.
Wildcards are permitted.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: .
Accept pipeline input: False
Accept wildcard characters: False
```

### -TenantId
The ID of the tenant where the Power BI workspace resides.

```yaml
Type: String
Parameter Sets: Default
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -WorkspaceName
The name of the Power BI workspace where the datasets are located.

```yaml
Type: String
Parameter Sets: Default
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Credential
A PSCredential object containing the credentials used for authentication.

```yaml
Type: PSCredential
Parameter Sets: Default
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -DatasetId
An optional array of dataset IDs to specify which datasets to test.
If not provided, all datasets will be tested.

```yaml
Type: Array
Parameter Sets: Default
Aliases:

Required: False
Position: Named
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
    - Message (String): The description of the event.
    - LogType (String): This is either Debug, Warning, Error, or Failure.
    - IsTestResult (Boolean): This indicates if the event was a test or not. 
This is helpful for filtering results.
    - DataSource: The location of the workspace (if in the service) or the localhost (if local testing) of the semantic model.
    - ModelName: The name of the semantic model.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: ADO
Accept pipeline input: False
Accept wildcard characters: False
```

### -CI
Enable Exit after Run.
When this switch is enable this will execute an "exit #" at the end of the module where "#" is the number of failed test cases.

```yaml
Type: SwitchParameter
Parameter Sets: Default
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

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