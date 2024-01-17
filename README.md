# fabric-dataops-patterns
Templates for weaving DataOps into Microsoft Fabric


## Testing Schema Template
These patterns show how to run schema checks against a semantic model. 

Dependencies: At least the December 2023 version of Power Desktop and [DAX Query View](https://learn.microsoft.com/en-us/power-bi/transform-model/dax-query-view).  Please make sure to turn on DAX Query View and PBIP preview features on.

[Schema.Tests.dax](./Semantic%20Model/SampleModel.Dataset/DAXQueries/Schema.Tests.dax): Example of running schema tests against a sample dataset.

[Schema Query Example](./Semantic%20Model/SampleModel.Dataset/DAXQueries/Schema%20Query%20Example.dax): Example of generating the DataTable syntax for the expected value part of the test case.

