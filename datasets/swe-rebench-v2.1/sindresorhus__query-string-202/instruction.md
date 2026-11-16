parseNumbers ignored with arrayFormat
The `parseNumbers` option does not get applied to values in an array.  e.g.:

```
const query = queryString.parse('?arrayOfNumbers=15,16,17&singleNumber=18', {
  parseNumbers: true,
  arrayFormat: 'comma',
});
```

Produces:

```
{
  arrayOfNumbers: ["15", "16", "17"],
  singleNumber: 18,
}
```

I was expecting it to produce:

```
{
  arrayOfNumbers: [15, 16, 17],
  singleNumber: 18,
}
```
