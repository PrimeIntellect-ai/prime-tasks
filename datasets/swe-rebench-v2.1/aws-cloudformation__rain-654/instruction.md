Rain incorrectly strips quotes from string values that resemble YAML booleans, altering data types in CloudFormation templates
Rain currently strips quotes from string values even when doing so changes the data type in CloudFormation. YAML treats certain unquoted words (`ON`, `OFF`, `YES`, `NO`, etc.) as booleans, but CloudFormation expects them as strings in certain parameters (e.g., `require_secure_transport` in `AWS::RDS::DBClusterParameterGroup`). This behavior leads to unintended type mismatches and deployment failures.

#### **Reproduction Steps**
Given the following CloudFormation template:
```yaml
Resources:
  DbClusterParameterGroupBlue:
    Type: AWS::RDS::DBClusterParameterGroup
    Properties:
      Description: "Aurora PG Cluster Parameter Group"
      Family: "aurora-mysql8.0"
      Parameters:
        require_secure_transport: "ON"
```
Running `rain fmt` or deploying via Rain strips the quotes:
```yaml
Parameters:
  require_secure_transport: ON
```
This causes CloudFormation to interpret `ON` as a boolean (`true`) instead of a string (`"ON"`), resulting in deployment issues.

#### **Why This is a Bug**
1. **Stripping Quotes Here Alters the Meaning of the Data**
   - Unlike normal YAML formatting, this is not just a stylistic change; it transforms a string into a boolean.

2. **Unexpected and Subtle Behavior**
   - This issue is difficult to debug because it happens at formatting time, and CloudFormation does not clearly indicate that the type changed due to YAML parsing.

3. **Existing Workarounds are Insufficient**
   - `--node-style original` is not a viable fix because:
     - It affects the entire template, not just the problematic values.
     - It prevents Rain from formatting other parts of the template where quotes should be stripped.
     - It is an opt-in fix rather than a default behavior correction.

#### **Suggested Fix**
Rain should **preserve quotes around string values that match YAML’s boolean-like keywords** (`ON`, `OFF`, `YES`, `NO`, `TRUE`, `FALSE`, etc.) to prevent unintentional type changes. This would ensure that templates maintain their intended behavior without requiring a global formatting override.

Related issue #480

### Additional contract requirements

- When formatting string scalar values `ON`, `OFF`, `Yes`, `No`, `True`, or `False`, Rain must render them with double quotes by default.
