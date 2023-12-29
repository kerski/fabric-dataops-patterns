# Synapse Analytics notebook source

# METADATA ********************

# META {
# META   "synapse": {
# META     "lakehouse": {
# META       "default_lakehouse": "37c04573-eac8-4774-9e22-45fd8d708048",
# META       "default_lakehouse_name": "CIExample",
# META       "default_lakehouse_workspace_id": "28b68708-e047-4f0b-a0d8-809219e494c1",
# META       "known_lakehouses": [
# META         {
# META           "id": "37c04573-eac8-4774-9e22-45fd8d708048"
# META         }
# META       ]
# META     },
# META     "environment": {
# META       "environmentId": "34d8f906-cce6-404d-a0b1-919f911c500f",
# META       "workspaceId": "28b68708-e047-4f0b-a0d8-809219e494c1"
# META     }
# META   }
# META }

# MARKDOWN ********************

# ## Import 
# *Note: The environment has semantic-link should be installed already*

# MARKDOWN ********************


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
dax_df = spark.sql("SELECT * FROM DAXQueries WHERE Azure_DevOps_Branch_Name = '" + branch + "' AND Dataset_Sub_Folder_Path LIKE '%.Tests.dax' AND Timestamp = (SELECT MAX(Timestamp) FROM DAXQueries)")

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

df = spark.sql("SELECT * FROM test_results LIMIT 10")
display(df)
