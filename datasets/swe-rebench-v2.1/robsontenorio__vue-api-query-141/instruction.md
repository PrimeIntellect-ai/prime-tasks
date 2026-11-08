Nested filters
The JSON Api spec supports nested filters as far as I'm aware:
`?filter[invoices][deadline]`

It would be nice if there was some sort of a clean support for it. The only way to achieve this for me was using params atm:

```javascript
params: {
          "filter[invoices][deadline]": null,
          "filter[invoices][state]": null
 }
//....
Model.params(params);
```

Anyway I think that passing an object to the filter function should add the params recursively

### Additional contract requirements

Nested filters can be added with `where` and `whereIn` by passing the nested filter path as an array of key segments. The path is emitted under the `filter` query parameter using bracketed keys; for example, `where(['user', 'status'], 'active')` produces `filter[user][status]=active`, and `whereIn(['user', 'status'], ['active', 'inactive'])` produces `filter[user][status]=active,inactive`.
