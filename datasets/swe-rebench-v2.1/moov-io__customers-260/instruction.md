Saving metadata only saves/returns the last{key: value} pair
Customers Version: `0.5.0-dev25`

**What were you trying to do?**
Save customer metadata


**What did you expect to see?**
All properties passed to be saved.


**What did you see?**
Only the last property in the request body is being saved


**How can we reproduce the problem?**
`PUT /customers/{customerID}/metadata`
Request
```json
{
   "metadata":{
      "keyone":"value",
      "keytwo":"valuetwo",
      "keythree":"valuethree"
   }
}
```
Response:
```json
{
...
   "metadata":{
      "keytwo":"valuetwo"
   },
...
}
```
