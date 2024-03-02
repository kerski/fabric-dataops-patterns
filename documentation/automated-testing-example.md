# Automating DAX Query View Testing Pattern

If you are using the [DAX Query View Testing Pattern](dax-query-view-testing-pattern.md) you can also look at automating the tests when a branch in your repository is updated and synced with a workspace through <a href="https://learn.microsoft.com/en-us/power-bi/developer/projects/projects-git" target="_blank">Git Integration</a>. The following instructions show you how to setup an Azure DevOps pipeline to automate testing.

## Prerequisites

1. You have an Azure DevOps project and have at least Project or Build Administrator rights for that project.

2. You have connected a premium-back capacity workspace to your a repository in your Azure DevOps project. Instructions are provided <a href="https://learn.microsoft.com/en-us/power-bi/developer/projects/projects-git" target="_blank">at this link.</a>

3. Your Power BI tenant has <a href="https://learn.microsoft.com/en-us/power-bi/enterprise/service-premium-connect-tools#enable-xmla-read-write" target="_blank">XMLA Read/Write Enabled</a>.

4. You have a service principal or account (username and password) with a Premium Per User license. If you are using a service principal you will need to make sure the Power BI tenant allows <a href="https://learn.microsoft.com/en-us/power-bi/enterprise/service-premium-service-principal#enable-service-principals">service principals to use the Fabric APIs</a>. The service prinicipal or account will need at least the Member role to the workspace.

## Instructions

### Create the Variable Group

1. In your project, navigate to the Pipelines->Library section.

![Variable Groups](./images/automated-testing-library.png)

1. Select the "Add Variable Group" button.

![Add Variable Group](./images/automated-testing-variable-group.png)

3. Create a variable group called "DevelopmentBranch" and create the following variables:

- WORKSPACE_NAME - The display name for the workspace.
- USERNAME_OR_CLIENTID - The service principal's application/client id or universal provider name for the account.
- PASSWORD_OR_CLIENTSECRET - The client secret or password for the service principal or account respectively.
- TENANT_ID - The Tenant GUID.  You can locate it by following the instructions <a href="https://learn.microsoft.com/en-us/sharepoint/find-your-office-365-tenant-id" target="_blank">at this link</a>.

![Create Variable Group](./images/automated-testing-create-variable-group.png)

4. Save the variable group.

![Save Variable Group](./images/automated-testing-save-variable-group.png)

### Create the Pipeline

1. Navigate to the pipeline interface.

![Navigate to Pipeline](./images/automated-testing-navigate-pipeline.png)

2. Select the "New Pipeline" button.

![New Pipeline](./images/automated-testing-create-pipeline.png)

3. Select the Azure Repos Git option.

![ADO Option](./images/automated-testing-ado-option.png)

4. Select the repository you have connected the workspace via Git Integration.

![Select Repo](./images/automated-testing-select-repo.png)

5. Copy the contents of the template YAML file located <a href="https://raw.githubusercontent.com/kerski/fabric-dataops-patterns/development/Azure%20DevOps/Automated%20Testing%20Example/Run-DaxTests.yml" target="_blank">at this link</a> into the code editor.

![Copy YAML](./images/automated-testing-copy-yaml.png)

6. Select the 'Save and Run' button.

![Save and Run](./images/automated-testing-save-pipeline.png)

7. You will be prompted to commit to the main branch. Select the 'Save and Run' button.

![Save and Run again](./images/automated-testing-save-and-run.png)

8. You will be redirected to the first pipeline run, and you will be asked to authorize the pipeline to access the variable group created previously.  Select the 'View' button.

9. A pop-up window will appear. Select the 'Permit' button.

![Permit](./images/automated-testing-permit.png)

10. You will be asked to confirm.  Select the 'Permit' button.

![Permit Again](./images/automated-testing-permit-again.png)

11. This will kick off the automated testing.

![Automated Job](./images/automated-testing-job-running.png)

12. Select the "Automated Testing Job".

![Select Job](./images/automated-testing-select-job.png)

13. You will see a log of DAX Queries that end in .Tests or .Test running against their respective semantic models in your workspace.

![Log](./images/automated-testing-log.png)

14. For any failed tests, this will be logged to the job, and the pipeline will also fail.

![Failed Tests](./images/automated-testing-failed-tests.png)