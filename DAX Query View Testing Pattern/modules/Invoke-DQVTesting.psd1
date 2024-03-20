@{  
    ModuleVersion = '0.1'  
    GUID = 'your-guid-here' # Replace with a unique GUID  
    Author = 'John Kerski'  
    CompanyName = 'kerski.tech' # Replace with your company name  
    Copyright = '(c) kerski.tech. All rights reserved.' # Replace with your company name  
    Description = 'This module run through the DAX Query View files that end with .Tests or .Test and output the results.'  
    RootModule = 'Invoke-DQVTesting.psm1'  
    FunctionsToExport = 'Invoke-DQVTesting'  
    PowerShellVersion = '7.1'  
    RequiredModules = @('Az.Accounts') # Include any other required modules here  
} 