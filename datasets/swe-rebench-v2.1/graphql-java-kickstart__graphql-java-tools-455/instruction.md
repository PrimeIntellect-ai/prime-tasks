Support for a catch-all field resolver
In my schema I support object synthetic properties via a **compute(expression: String!)** method which does its job allowing me to return to a query any number of results. GraphQL specification allows renaming them in the result set by specifying aliases in the query:
```javascript
positions
{
    house_shorts
    house_longs
    nominal_short: compute(expression: "self.house_shorts * self.price")
    nominal_long: compute(expression: "self.house_longs * self.price")
}
```
This is all good but the problem is that I would like to be able to reference these properties further away in the query:
```
stream
{
    positions
    {
        ...
        nominal_short(expression: "self.house_shorts * self.price)
        nominal_long(expression: "self.house_longs * self.price")
    }
    filter(expression: "self.positions.nominal_short > 1000000 or self.positions.nominal_long > 1000000")
    {
        list
        {
            nominal_short
            nominal_long
        }
    }
}
```
In the latter query **positions, nominal_** are properties created at runtime and they cannot be resolved by the current implementation of this library. However, if the library would have a MissingFieldResolver which instead of throwing an exception would simply allow for calling a user defined handler things could work out differently. The handler can use a Map to associate "missing" properties with their values. A type resolver could implement a method, tag it with an annotation @GenericFieldResolver and return the value from it.

### Additional contract requirements

- `SchemaParserOptions.newOptions()` returns a builder for schema parser options.
- The builder exposes a method `missingResolverDataFetcher(DataFetcher<Any?>)` that configures a fallback data fetcher used for fields that have no resolver defined in the schema. The method returns the same builder instance so that option setters can be chained.
- When a field has no resolver and a fallback data fetcher is configured, the fallback data fetcher is invoked for that field instead of an error being raised.
