CREATE TABLE [dbo].[dax_queries] (
    [Workspace_GUID]                     VARCHAR (8000) NULL,
    [Azure_DevOps_Branch_Name]           VARCHAR (8000) NULL,
    [Repository_ID]                      VARCHAR (8000) NULL,
    [Commit_ID]                          VARCHAR (8000) NULL,
    [Object_ID]                          VARCHAR (8000) NULL,
    [Dataset_Name]                       VARCHAR (8000) NULL,
    [Dataset_Sub_Folder_Path]            VARCHAR (8000) NULL,
    [URL]                                VARCHAR (8000) NULL,
    [Is_File_For_Continuous_Integration] BIT            NULL,
    [DAX_Queries]                        VARCHAR (8000) NULL,
    [Timestamp]                          DATETIME2 (6)  NULL,
    [Concatenated_Key]                   VARCHAR (8000) NULL
);
GO

