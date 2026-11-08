Setting an extension on a StructureDefinition
We're trying to set the value of an extension on the underlying StructureDefinition for a profile we're defining by using the "escape syntax" (^):
```
Profile: NewOnsetOfT2DMDataElementCPG3
Parent: Observation
* ^extension[inferenceExpression].valueExpression.language = #text/cql
* ^extension[inferenceExpression].valueExpression.expression =
  "exists([Condition in \"T2DMConditionVS\"] c where c.onset is within last 2 months)"
* code = ExampleCdsCS#t2dm
```

Which builds fine, but it seems to be treating the `.valueExpression.language` part as constraints, rather than instance assignments...
```
"extension": [
    {
      "_sliceName": "inferenceExpression",
      "valueExpression": {
        "language": {
          "fixedValue": "text/cql",
          "_primitive": true
        },
        "expression": {
          "fixedValue": "exists([Condition in \"T2DMConditionVS\"] c where c.onset is within last 2 months)",
          "_primitive": true
        }
      }
    }
  ]
```
