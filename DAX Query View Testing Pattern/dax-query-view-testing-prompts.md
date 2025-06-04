# Copilot Fabric for DAX Query View

This is a work in progress, but here is a library of prompts to create starting points for tests using the DAX Query View Testing Pattern.

Requires [DAX query view with Copilot.](https://powerbi.microsoft.com/en-us/blog/power-bi-march-2024-feature-summary/#post-26258-_Toc32386165)


## Generate and Evaluate Template DAX Test Cases for Semantic Model
```
Please generate a set of 3 template test cases, as a ROW, for this semantic model with the following columns:
1) TestName - This should describe the test conducted and be less than 255 characters
2) ExpectedValue - The expected value for the test.
3) ActualValue - The actual value returned from the DAX query.

Output as a variable called _Tests.

Then Evaluate _Tests by comparing each actual value with the expected value to see if they match and output the Boolean column called Passed 
```

## Generate Test Cases for Each Measure
```
Please generate a test case for each measure in the semantic model with the following columns:
1) TestName - This should describe the test conducted and be less than 255 characters
2) ExpectedValue - The expected value for the test.
3) ActualValue - The actual value returned from the DAX query.

Output as a variable called _Tests.

Then Evaluate _Tests by comparing each actual value with the expected value to see if they match and output the Boolean column called Passed 
```

## Generate and Validate Uniqueness Tests for Key Columns
```
Please generate a test case for each column marked as a key column with a test of its uniqueness the following columns:
1) TestName - This should describe the test conducted and be less than 255 characters
2) ExpectedValue - The expected value for the test.
3) ActualValue - The actual value returned from the DAX query.

Output as a variable called _Tests.

Then Evaluate _Tests by comparing each actual value with the expected value to see if they match and output the Boolean column called Passed 
```

## Generate and Validate Numeric Measures Default to 0 on No Rows (Instead of Blank)
```
For each measure that is a numeric type, please generate a test that when no rows are present it coalesces to -999 using the following columns:
1) TestName - This should describe the test conducted and be less than 255 characters
2) ExpectedValue - The expected value for the test should be 0
3) ActualValue - The actual value returned from the DAX query.

Output as a variable called _Tests.

Then Evaluate _Tests by comparing each actual value with the expected value to see if they match and output the Boolean column called Passed 
```
