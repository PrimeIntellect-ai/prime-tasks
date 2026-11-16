[HIDDEN]
In JSON processor, we have this code to remove keys found in a JSON payload from query parameters

https://github.com/corazawaf/coraza/blob/v3/dev/bodyprocessors/json.go#L28

How query parameters and JSON payload get merged is completely app-specific, so removing variables from query from processing seems dangerous, e.g. especially without multiphase evaluation, a log4shell trigger in query parameter seems like it would be allowed if it's together with a JSON payload.

[HIDDEN] and let the value be present in both locations?

### Additional contract requirements

- When the same key appears in the query parameters and the JSON payload, its value must remain available in both locations; appearing in the JSON payload must not suppress the query parameter.
