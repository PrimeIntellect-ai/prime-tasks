Group by does not allow multiple fields
<!--
  Please include the following classification.
  If your classification is not added, you can modify the list below
-->
- [ ] Feature
- [x] Bug Request

<!--If this is a bug, please include the steps to reproduce the bug-->
## Description

The following query is listed as invalid, but it is valid syntax.

```sql
SELECT BillingState, BillingStreet, COUNT(Id)
FROM Account
GROUP BY BillingState, BillingStreet
```

Expected output (based on current data model):
```typescript
      fields: [
        { type: 'Field', field: 'BillingState' },
        { type: 'Field', field: 'BillingStreet' },
        {
          type: 'FieldFunctionExpression',
          functionName: 'COUNT',
          rawValue: 'COUNT(Id)',
          isAggregateFn: true,
          parameters: ['Id'],
        },
      ],
      sObject: 'Account',
      groupBy: { field: ['BillingState', 'BillingStreet'] },
```
