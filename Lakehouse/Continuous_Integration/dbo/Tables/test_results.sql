CREATE TABLE [dbo].[test_results] (
    [Run_GUID]         VARCHAR (8000) NULL,
    [Test_Name]        VARCHAR (8000) NULL,
    [Expected_Value]   VARCHAR (8000) NULL,
    [Actual_Value]     VARCHAR (8000) NULL,
    [Passed]           BIT            NULL,
    [Concatenated_Key] VARCHAR (8000) NULL,
    [Timestamp]        DATETIME2 (6)  NULL
);
GO

