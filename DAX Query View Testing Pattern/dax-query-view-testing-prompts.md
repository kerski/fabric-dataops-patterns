# Copilot Fabric for DAX Query View

This is a work in progress, but here is a library of prompts to create starting points for tests using the DAX Query View Testing Pattern.

Requires [DAX query view with Copilot.](https://powerbi.microsoft.com/en-us/blog/power-bi-march-2024-feature-summary/#post-26258-_Toc32386165)


## Bootstrap Prompt for Measures
Create template to build a test for each measure in the semantic model.

```
Generate a test case for each measure with the following columns:
1) TestName - This should describe the test conducted and be less than 255 characters
2) ExpectedValue - The expected value for the test.
3) ActualValue - The actual value returned from the DAX query.
4) Passed - A boolean value that compares ExpectedValue and ActualValue
The test should compare a static value with the measure to see if they match. 
```

## Tables Have Data prompt
```
Generate a test case for each table that checks the table has more than zero rows using the COUNTROWS function. The output should contain following columns:
1) TestName - This should describe the test conducted and be less than 255 characters
2) ExpectedValue - The expected value for the test.
3) ActualValue - The actual value returned from the COUNTROWS function.
4) Passed - A boolean value that compares ExpectedValue and ActualValue
```

## Column statistics prompt
Replace {TABLE} with the name of the table in your model.
```
For the column statistics in {TABLE} create a DAX that outputs the following columns:
1) TestName - This should describe the test
2) ExpectedValue - The expected value for the test
3) ActualValue - The actual value returned from the DAX query
4) Passed - A boolean value that compares ExpectedValue and ActualValue
Also try to create tests for the following columns:
1) For keys, that column should be unique
2) For non-key numerics, the column should be within the min and max range
```

## N/A check
```
For each numeric measure please create a test that outputs the following columns:
1) TestName - This should describe the test
2) ExpectedValue - The expected value for the test
3) ActualValue - The actual value returned from the DAX query
4) Passed - A boolean value that compares ExpectedValue and ActualValue
The test should apply a filter the reduces the rows to 0 and checks if the output is 0 instead of blank.  
The test should use the NOT and ISBLANK functions.
```