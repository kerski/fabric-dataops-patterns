CREATE VIEW [Test Results] AS
WITH tests As (
SELECT ROW_NUMBER() OVER(ORDER BY Test_Name ASC) AS 'Row Number',
    DENSE_RANK() OVER (ORDER BY [Timestamp] DESC) as 'Rank',
    [Timestamp],
    Run_GUID as 'Run GUID',
    Test_Name as 'Test Name',
    Expected_Value as 'Expected Value',
    Actual_Value as 'Actual Value',
    Passed,
    CAST(Passed AS INT) as 'Passed As Integer',
    Concatenated_Key as 'Concatenated Key'
    FROM test_results
)
SELECT 
    t.[Row Number],
    t.[Rank],
    t.[Test Name],
    t.[Expected Value],
    t.[Actual Value],
    t.[Passed],
    t.[Passed As Integer],
    t.[Timestamp],
    t.[Concatenated Key]
FROM tests as t
GO

