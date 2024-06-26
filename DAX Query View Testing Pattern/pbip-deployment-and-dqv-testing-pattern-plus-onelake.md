# PBIP Deployment & DAX Query View Testing (DQV) Pattern + OneLake

If you are using the [DAX Query View Testing Pattern](dax-query-view-testing-pattern.md) you can also look at automating the deployment and testing using Azure DevOps. The following instructions show you how to setup an Azure DevOps pipeline to automate deployment of Power BI reports/semantic models and automate testing. In addition, test results can be sent to OneLake in your Fabric Capacity for processing.

## Table of Contents
- [PBIP Deployment \& DAX Query View Testing (DQV) Pattern(#pbip-deployment--dax-query-view-testing-dqv-pattern)
  - [Table of Contents](#table-of-contents)
  - [High-Level Process](#high-level-process)
  - [Prerequisites](#prerequisites)
  - [Instructions](#instructions)
    - [Create the Variable Group](#create-the-variable-group)
    - [Create the Pipeline](#create-the-pipeline)
  - [Monitoring](#monitoring)
  - [Powershell Modules](#powershell-modules)

## High-Level Process

![Figure 1](../documentation/images/automated-testing-with-log-shipping-high-level.png)
*Figure 1 -- High-level diagram of automated deployment of PBIP and automated testing with the DAX Query View Testing Pattern*

In the pattern depicted in Figure 1, your team saves their Power BI work in the PBIP extension format and commits those changes to Azure DevOps.

Then an Azure Pipeline is triggered to validate the content of your Power BI semantic models and reports by performing the following:

1.  The semantic model changes are identified using the "git diff" command. Semantic models that are changed are published to a premium-backed workspace using <a href="https://github.com/microsoft/Analysis-Services/tree/master/pbidevmode/fabricps-pbip" target="_blank">Rui Romano\'s Fabric-PBIP script</a>. The question now is, which workspace do you deploy it to? I typically promote to a ***Build*** workspace first, which provides an area to validate the content of the semantic model before promoting to a ***development*** workspace that is shared by others on the team. This reduces the chances that a team member introduces an error in the ***Development*** workspace that could hinder the work being done by others in that workspace.

2.  With the semantic models published to a workspace, the report changes are identified using the "git diff" command. Report changes are evaluated for their "definition.pbir" configuration. If the byConnection property is null (meaning the report is not a thin report), the script identifies the local semantic model (example in Figure 2). If the byConnection is not null, we assume the report is a thin report and configured appropriately. Each report that has been updated is then published in the same workspace.

    ![Figure 2](../documentation/images/pbip-deployment-and-dqv-testing-pbir.png)
    *Figure 2 - Example of. pbir definition file*

3.  For the semantic models published in step 1, the script then <a href="https://learn.microsoft.com/en-us/power-bi/guidance/powerbi-implementation-planning-content-lifecycle-management-validate" target="_blank">validates the functionality</a> of the semantic model through a synchronous refresh using <a href="https://www.powershellgallery.com/packages/Invoke-SemanticModelRefresh/0.0.2" target="_blank">Invoke-SemanticModelRefresh</a>. Using the native <a href="https://learn.microsoft.com/en-us/rest/api/power-bi/datasets/refresh-dataset" target="_blank">v1.0 API</a> would be problematic because it is asynchronous, meaning if you issue a refresh you only know that the semantic model refresh has kicked off, but not if it was successful. To make it synchronous, I've written a module that will issue an enhanced refresh request to get a request identifier (a <a href="https://en.wikipedia.org/wiki/Universally_unique_identifier" target="_blank">GUID</a>). This request identifier can then be passed as parameter to the <a href="https://learn.microsoft.com/en-us/rest/api/power-bi/datasets/get-refresh-execution-details" target="_blank">Get Refresh Execution Details</a> endpoint to check on that specific request's status and find out whether or not the refresh has completed successfully.
    <br/><br/>
    If the refresh is successful, we move to step 4. Note: The first time a new semantic is placed in the workspace, the refresh will fail. You have to "prime" the pipeline and set the data source credentials manually. As of April 2024, this is not fully automatable and the Fabric team at Microsoft <a href="https://powerbi.microsoft.com/en-us/blog/using-xmla-endpoints-to-change-data-sources-in-a-power-bi-dataset/" target="_blank">has written about</a>.

4.  For each semantic model, Invoke-DQVTesting is called to run the DAX Queries that follow the DAX Query View Testing Pattern. Results are then logged to the Azure DevOps pipeline (Figure 3). Any failed test will fail the pipeline.

![Figure 3](../documentation/images/pbip-deployment-and-dqv-testing-log.png)
*Figure 3 - Example of test results logged by Invoke-DQVTesting*

5. The results of the tests collected by Invoke-DQVTesting are also sent to OneLake where there reside in a Lakehouse on your Fabric Capacity.  These can then be used for processing, analyses, and notifications.

## Prerequisites

1. You have an Azure DevOps project and have at least Project or Build Administrator rights for that project.

2. You have connected a **Fabric-backed** capacity workspace to your repository in your Azure DevOps project. Instructions are provided <a href="https://learn.microsoft.com/en-us/power-bi/developer/projects/projects-git" target="_blank">at this link.</a>

3. Your Power BI tenant has <a href="https://learn.microsoft.com/en-us/power-bi/enterprise/service-premium-connect-tools#enable-xmla-read-write" target="_blank">XMLA Read/Write Enabled</a>.

4. You have a service principal. If you are using a service principal you will need to make sure the Power BI tenant allows <a href="https://learn.microsoft.com/en-us/power-bi/enterprise/service-premium-service-principal#enable-service-principals">service principals to use the Fabric APIs</a>. The service prinicipal or account will need at least the Member role to the workspace.

5. You have an existing Lakehouse created. Instructions can be found <a href="https://learn.microsoft.com/en-us/fabric/data-engineering/tutorial-build-lakehouse#create-a-lakehouse" target="_blank">at this link</a>.

## Instructions

### Capture Lakehouse Variables

1. Navigate to the Lakehouse in the Fabric workspace.

2. Inspecting the URL and capture the Workspace ID and Lakehouse ID. Copy locally to a text file (like Notepad).

![Workspace and Lakehouse ID](../documentation/images/automated-testing-with-log-shipping-workspace-and-lakehouse-ids.png)

3. Access the Files' properties by hovering over the Files label, select the option '...' and select Properties.

![Access Properties](../documentation/images/automated-testing-with-logging-get-link.png)

4. Copy the URL to your local machine temporarily in Notepad.  Append the copied URL with the text ‘DQVTesting/raw’. This allows us to ship the test results to a specific folder in your Lakehouse.
For example if your URL for the Files is:
   - https://onelake.dfs.fabric.microsoft.com/xxxxx-48be-41eb-83a7-6c1789407037/a754c80f-5f13-40b1-ab93-e4368da923c4/Files
   - The updated URL is  https://onelake.dfs.fabric.microsoft.com/xxxxx-48be-41eb-83a7-6c1789407037/a754c80f-5f13-40b1-ab93-e4368da923c4/Files/DQVTests/raw
  

### Setup the Notebook and Lakehouse

5. Download the Notebook locally from <a href="./scripts/Load Test Results.ipynb" target="_blank">this location</a>.

6. Navigate to the <a href="https://app.powerbi.com/home?experience=data-engineering" target="_blank">Data Engineering Screen</a> and import the Notebook.

![Import Notebook](../documentation/images/automated-testing-with-log-shipping-import-notebook.png)

7. Open the notebook and update the parameterized cell's workspace_id and lakehouse_id with the ids you retrieved in Step 

![Setup parameters in Notebook](../documentation/images/automated-testing-with-log-shipping-setup-notebook-parameters.png)

8. If you have not connected the Notebook to the appropriate lakehouse, please do so.  Instructions are <a href="https://learn.microsoft.com/en-us/fabric/data-engineering/how-to-use-notebook#connect-lakehouses-and-notebooks" target="_blank">provided here</a>. 

9. Run the Notebook. This will create the folders for processing the test results.

![Folders created](../documentation/images/automated-testing-with-log-shipping-folders-created.png)

### Create the Variable Group in Azure DevOps

10. In your Azure DevOps project, navigate to the Pipelines->Library section.

![Variable Groups](../documentation/images/automated-testing-library.png)

11. Select the "Add Variable Group" button.

![Add Variable Group](../documentation/images/automated-testing-variable-group.png)

12. Create a variable group called "TestingCredentialsLogShipping" and create the following variables:

- ONELAKE_ENDPOINT - Copy the URL from Step 4 into this variable.
![OneLake Properties URL](../documentation/images/automate-testing-onlake-properties-url.png)
- CLIENT_ID - The service principal's application/client id or universal provider name for the account.
- CLIENT_SECRET - The client secret or password for the service principal or account respectively.
- TENANT_ID - The Tenant GUID.  You can locate it by following the instructions <a href="https://learn.microsoft.com/en-us/sharepoint/find-your-office-365-tenant-id" target="_blank">at this link</a>.

![Create Variable Group](../documentation/images/automated-testing-with-logging-shipping-create-variable-group.png)

13. Save the variable group.

![Save Variable Group](../documentation/images/automated-testing-with-log-shipping-save-variable-group.png)

### Create the Pipeline

14. Navigate to the pipeline interface.

![Navigate to Pipeline](../documentation/images/automated-testing-navigate-pipeline.png)

15. Select the "New Pipeline" button.

![New Pipeline](../documentation/images/automated-testing-create-pipeline.png)

16. Select the Azure Repos Git option.

![ADO Option](../documentation/images/automated-testing-ado-option.png)

17. Select the repository you have connected the workspace via Git Integration.

![Select Repo](../documentation/images/automated-testing-select-repo.png)

18. Copy the contents of the template YAML file located <a href="https://raw.githubusercontent.com/kerski/fabric-dataops-patterns/main/DAX%20Query%20View%20Testing%20Pattern/scripts/Run-CICD-Plus-OneLake.yml" target="_blank">at this link</a> into the code editor.

![Copy YAML](../documentation/images/pbip-deployment-and-dqv-testing-copy-yaml.png)

19. Update the default workspace name for located on line 5 with the workspace you will typically use to conduct testing.

![Update workspace parameter](../documentation/images/pbip-deployment-and-dqv-testing-update-workspace-parameter.png)

20. Select the 'Save and Run' button.

![Save and Run](../documentation/images/pbip-deployment-and-dqv-testing-save-pipeline.png)

21. You will be prompted to commit to the main branch. Select the 'Save and Run' button.

![Save and Run again](../documentation/images/automated-testing-save-and-run.png)

22. You will be redirected to the first pipeline run, and you will be asked to authorize the pipeline to access the variable group created previously.  Select the 'View' button.

23. A pop-up window will appear. Select the 'Permit' button.

![Permit](../documentation/images/automated-testing-permit.png)

24. You will be asked to confirm.  Select the 'Permit' button.

![Permit Again](../documentation/images/automated-testing-permit-again.png)

25. This will kick off the automated deployment and testing as [described above](#high-level-process).

![Automated Job](../documentation/images/pbip-deployment-and-dqv-testing-job-running.png)

26. Select the "Automated Deployment and Testing Job".

![Select Job](../documentation/images/pbip-deployment-and-dqv-testing-select-job.png)

27. You will see a log of DAX Queries that end in .Tests or .Test running against their respective semantic models in your workspace.

![Log](../documentation/images/pbip-deployment-and-dqv-testing-log.png)

28. For any failed tests, this will be logged to the job, and the pipeline will also fail.

![Failed Tests](../documentation/images/automated-testing-failed-tests.png)

29.  You will also see any test results in your lakehouse as a CSV file. Please see [CSV Format](#csv-format) for more details on the file format.

![Logged Test Results](../documentation/images/automated-testing-logged-results.png)

### Run the Notebook

30.   Run the notebook and when completed the files should be moved into the processed folder and following tables are created in the lakehouse:
- Calendar - The date range of the test results.
- ProjectInformation - A table containing information about the Azure DevOps project and pipeline used to execute the test results.
- TestResults - Table containing test results.
- Time - Used to support time-based calculations.

  
![View Tables](../documentation/images/automated-testing-with-logging-shipping-view-tables.png)

1.  Schedule the notebook to run on a regular interval as needed. Instructions can be found <a href="https://learn.microsoft.com/en-us/fabric/data-factory/notebook-activity#save-and-run-or-schedule-the-pipeline" target="_blank">at this link</a>.

## Monitoring

It's essential to monitor the Azure DevOps pipeline for any failures. I've also written about some best practices for setting that up <a href="https://www.kerski.tech/bringing-dataops-to-power-bi-part31/" target="_blank">in this article</a>.

## CSV Format
The following describes the CSV file columns for each version of Invoke-DQVTesting.

### Version 0.0.10

1. Message - The message logged for each step of testing.
2. LogType - Will be either of the following values:
   - Debug - Informational purposes.
   - Error - A test has failed.
   - Failed - One or more tests failed.
   - Success - All tests passed.
   - Passed - Test result passed.
3. IsTestResult - Will be "True" for if the record was a test.  "False" otherwise.
4. DataSource - The XMLA endpoint for the semantic model.
5. ModelName - The name of the semantic model.
6. BranchName - The name of the branch of the repository this testing occurred in.
7. RespositoryName - The name of the respository this testing occurred in.
8. ProjectName - The name of the Azure DevOps project this testing occurred in.
9.  UserName - The initiator of the test results in Azure DevOps.
10. RunID - Globally Unique Identifier to identify the tests conducted.
11. Order - Integer representing the order in which each record was created.
12. RunDateTime - ISO 8601 Format the Date and Time the tests were initiated.
13. InvokeDQVTestingVersion - The version of Invoke-DQVTesting used to conducted the tests.

## Powershell Modules

The pipeline leverages two PowerShell modules called Invoke-DQVTesting and Invoke-SemanticModelRefresh.  For more information, please see [Invoke-DQVTesting](invoke-dqvtesting.md) and [Invoke-SemanticModelRefresh](invoke-semanticmodelrefresh.md) respectively.

*Git Logo provided by [Git - Logo Downloads
(git-scm.com)](https://git-scm.com/downloads/logos)*
