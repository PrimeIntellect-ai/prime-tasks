Missing Value Node in `sh:uniqueLang` Constraint Validation Report
### Version

5.3.0

### What happened?

#### **Issue Description**
When the `sh:uniqueLang` constraint is violated, the validation report does not include the duplicated value node. This makes it difficult to identify which specific values caused the violation.

#### **Expected Behavior**
The validation report should provide the duplicated value node, allowing users to pinpoint the exact issue in their data.

#### **Steps to Reproduce**
1. Define a SHACL shape with `sh:uniqueLang true`.
2. Validate data that contains multiple values with the same language tag for a property.
3. Observe the validation report.

#### **Actual Behavior**
- The validation report states that the constraint was violated but does not indicate the specific duplicated value node.

#### **Expected Behavior**
- The validation report should include the exact value nodes that caused the violation.

#### **Example**
##### **SHACL Shape**
```turtle
ex:BuildingShape a sh:NodeShape ;
    sh:targetClass ex:Building ;
    sh:property [
        sh:path ex:label ;
        sh:datatype rdf:langString ;
        sh:uniqueLang true ;
        sh:message "Each building label should have only one value per language." ;
    ] .
```

##### **Invalid Data**
```turtle
ex:Building1 a ex:Building ;
    ex:label "Building"@en , "Edifice"@en , "Gebäude"@de .
```

### Relevant output and stacktrace

```shell

```

### Are you interested in making a pull request?

Yes
