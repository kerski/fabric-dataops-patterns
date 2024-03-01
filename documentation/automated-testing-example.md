# Automating DAX Query View Testing Pattern

If you are using the [DAX Query View Testing Pattern](dax-query-view-testing-pattern.md) you can then look at automating the tests when a branch in your repository is updated and synced with a workspace through <a href="https://learn.microsoft.com/en-us/power-bi/developer/projects/projects-git" target="_blank">Git Integration</a>. The following instructions show you how to setup a pipeline.

## Prerequisites

1. You have an Azure DevOps project and have at least Project or Build Administrator rights for that project.

2. You have connected a premium-back capacity workspace. Instructions are provided <a href="https://learn.microsoft.com/en-us/power-bi/developer/projects/projects-git" target="_blank">at this link.</a>

3. Your Power BI tenant has <a href="https://learn.microsoft.com/en-us/power-bi/enterprise/service-premium-connect-tools#enable-xmla-read-write" target="_blank">XMLA Read/Write Enabled</a>.

4. You have a service principal or account (username and password) with a Premium Per User license. If you are using a service principal you will need to make sure the Power BI tenant allows <a href="https://learn.microsoft.com/en-us/power-bi/enterprise/service-premium-service-principal#enable-service-principals">service principals are to use the APIs</a>. The service prinicipal or account with at least the Viewer role to the workspace.

## Instructions

### Create the Variable Group

1. In your project navigate to the Pipelines->Library section.

![Variable Groups](./images/automated-testing-library.png)

1. Select the "Add Variable Group" button.

![Add Variable Group](./images/automated-testing-variable-group.png)

3. Create a variable group called "ProductionBranch" and create the following variables:

- WORKSPACE_NAME - The display name for the workspace.
- USERNAME_OR_CLIENTID - The service principal's application/client id or universal provider name for the account.
- PASSWORD_OR_CLIENTSECRET - The client secret or password for the service principal or account respectively.

![Create Variable Groups](./images/automated-testing-create-variable-group.png)

4. Save the variable group.

### Create the Pipeline

1. Navigate the pipeline interface.

![Navigate to Pipeline](./images/automated-testing-navigate-pipeline.png)

2. Select the "New Pipeline" button.

![New Pipeline](./images/automated-testing-create-pipeline.png)

3. Select the Azure Repos Git option.

![ADO Option](./images/automated-testing-ado-option.png)

4. Select the repository you have connected to the workspace via Git Integration.

![Select Repo](./images/automated-testing-select-repo.png)

5. Copy the contents of template YAML file located <a href="" target="_blank">at this link</a>.

