Issue with map operation
Hey @diegoholiveira

I'm having an issue when using `map` operation. Basically I'm trying to iterate over an array of arrays, and then using the `in` operation to evaluate for every given array if the passed argument is present in each one. My rule looks like this:
```json
{
  "map": [
    {
      "var": "listOfLists"
    },
    {
      "in": [
        "item_a",
        {
          "var": ""
        }
      ]
    }
  ]
}
```
And the input data:
```json
{
  "listOfLists": [
    ["item_a", "item_b", "item_c"],
    ["item_b", "item_c"],
    ["item_a", "item_c"]
  ]
}
```
So basically I expect to get an array of booleans as output, that informs me for every list if `item_a` was present:
```json
[
    true,
    false,
    true
]
```
But for some reason, this is what I'm getting:
```json
[
    true,
    true
]
```
It looks like it's ignoring false values, showing only the true ones. For the record, I ran the test in the [JsonLogic site](https://jsonlogic.com/play.html) and I get the result I was expecting, so I think It could be an issue with the map implementation.
Thanks!
