toApiFormat doesn't preserve structure of arrays and array-like objects
Examples:

```js
> toApiFormat({substitution_data: {objs: {"3": 3, "10": 10}}})
{ substitution_data: { objs: [ , , , 3, , , , , , , 10 ] } }
> in = {array: [0, 1, , , , , 6]};
{ array: [ 0, 1, , , , , 6 ] }
> out = toApiFormat(o)
{ array: [ 0, 1, undefined, undefined, undefined, undefined, 6 ] }
> Object.keys(in.array)
[ '0', '1', '6' ]
> Object.keys(out.array)
[ '0', '1', '2', '3', '4', '5', '6' ]
```

This manifested itself by converting an object with a couple sparse, numeric keys into an array with 90k undefined values, resulting in: `{ message: 'Substitution data too large', description: 'Transmission-level substitution data must be less than 100000 bytes', code: '2002' }` despite not sending nearly that much data to the `sparkpost.transmissions.send()` call.

I have a PR ready: https://github.com/SparkPost/node-sparkpost/pull/148
