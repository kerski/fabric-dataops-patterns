# Synapse Analytics notebook source

# METADATA ********************

# META {
# META   "synapse": {
# META     "lakehouse": {
# META       "default_lakehouse": "ef820c8b-50ab-43f9-9490-30a63c2534de",
# META       "default_lakehouse_name": "Continuous_Integration",
# META       "default_lakehouse_workspace_id": "66563acf-9df8-4e25-a960-25237d1e5e2e",
# META       "known_lakehouses": [
# META         {
# META           "id": "ef820c8b-50ab-43f9-9490-30a63c2534de"
# META         }
# META       ]
# META     },
# META     "environment": {
# META       "environmentId": "64bf71c8-1c40-4017-aaef-cff20ccff958",
# META       "workspaceId": "66563acf-9df8-4e25-a960-25237d1e5e2e"
# META     }
# META   }
# META }

# MARKDOWN ********************

# ## Import 
# *Note: The environment has semantic-link should be installed already*

# CELL ********************

import sempy.fabric as fabric
from pyspark.sql import SparkSession
from pyspark.sql.functions import udf
from pyspark.sql.functions import col
from pyspark.sql.types import *
import uuid
import datetime

# MARKDOWN ********************

# ## Set Branch Parameter

# CELL ********************

branch = "main"


# MARKDOWN ********************

# ## Retrieve DAX Queries

# PARAMETERS CELL ********************

# Generate Run Guid
run_uuid = str(uuid.uuid4())
# Generate Timestamp
run_dt = datetime.datetime.now()

# Get latest queries for the branch
# NOTE: Switch to commit id for orchestration
dax_df = spark.sql("SELECT * FROM Continuous_Integration.dax_queries WHERE Azure_DevOps_Branch_Name = '" + branch + "' AND Dataset_Sub_Folder_Path LIKE '%.Tests.dax' AND Timestamp = (SELECT MAX(Timestamp) FROM Continuous_Integration.dax_queries)")

display(dax_df)


# CELL ********************

# Create empty schema
test_schema = StructType(
                    [StructField('Run_GUID',
                                StringType(), True),
                    StructField('Test_Name',
                                StringType(), True),
                    StructField('Expected_Value',
                                  StringType(), True),
                    StructField('Actual_Value',
                                StringType(), True),
                    StructField('Passed',
                                BooleanType(), True),
                    StructField('Concatenated_Key',
                                StringType(), True),
                    StructField('Timestamp',
                                TimestampType(), True)])                                



# MARKDOWN ********************

# ### Run Tests
# Iterates through DAX Queries, runs the tests and saves the results to test_results.

# CELL ********************


# Itertuples
dax_df2 = dax_df.toPandas()
# Possible a faster way, but this works for now
for row in dax_df2.itertuples():
    dqs = fabric.evaluate_dax(row.Dataset_Name,row.DAX_Queries, row.Workspace_GUID)
    # Retrieve
    test = dqs[['[TestName]','[ExpectedValue]','[ActualValue]','[Passed]']]
    # Set Concatenated Key
    test['Concatenated_Key'] = row.Concatenated_Key
    test['Run_GUID'] = run_uuid
    test['Test_Name'] = test['[TestName]']
    test['Expected_Value'] = test['[ExpectedValue]']
    test['Actual_Value'] = test['[ActualValue]']
    test['Passed'] = test['[Passed]']
    test['Timestamp'] = run_dt

    test_results = test[['Run_GUID','Test_Name','Expected_Value','Actual_Value','Passed','Concatenated_Key','Timestamp']]
    display(test_results)
    test_results.to_lakehouse_table("test_results", "append", test_schema)



# MARKDOWN ********************

# ## Output Test Results

# CELL ********************

df = spark.sql("SELECT * FROM test_results LIMIT 1000")
display(df)
