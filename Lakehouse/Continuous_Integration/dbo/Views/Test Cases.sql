CREATE VIEW [Test Cases] AS 
WITH daxq AS(
    SELECT ROW_NUMBER() OVER(ORDER BY Concatenated_Key ASC) AS 'Row Number',
    Dataset_Name as 'Dataset Name',
    Azure_DevOps_Branch_Name as 'Branch Name',
    DAX_Queries as 'DAX Query',
    Commit_ID as 'Commit ID',
    Workspace_GUID as 'Workspace GUID',
    Concatenated_Key as 'Concatenated Key'
    FROM dax_queries 
    WHERE Is_File_For_Continuous_Integration = 1
)

Select 
    *
 FROM daxq
GO

