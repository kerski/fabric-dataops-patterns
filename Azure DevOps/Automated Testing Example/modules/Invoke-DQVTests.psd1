@{  
    ModuleVersion = '1.0'  
    GUID = 'your-guid-here' # Replace with a unique GUID  
    Author = 'John Kerski'  
    CompanyName = 'your-company-name-here' # Replace with your company name  
    Copyright = '(c) your-company-name-here. All rights reserved.' # Replace with your company name  
    Description = 'This module run through the DAX Query View files that end with .Tests or .Test and output the results.'  
    RootModule = 'PowerBITests.psm1'  
    FunctionsToExport = 'Test-PowerBIDatasets'  
    PowerShellVersion = '5.1'  
    RequiredModules = @('Az.Accounts') # Include any other required modules here  
} 