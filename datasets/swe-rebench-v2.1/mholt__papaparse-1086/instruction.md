Data corruption in 5.5.1 when streaming data with step function
We recently tried upgrading from 5.4.1 to 5.5.1 and encountered this error

We started seeing `Duplicate headers found and renamed` in the logs and noticed that our data was corrupted.

It seems that instead of deduplicating just the header row, it deduplicates all the data in each row too.

You can reproduce with this file:
```
const Papa = require("papaparse");

const csv = `a,b,c,c
d,d,e,e
d,f,f,g`;

Papa.parse(csv, {
    header: true,
    step: function(results) {
        console.log(results.data);
    },
    complete: function() {
        console.log("Parsing complete");
    }
});
```


In 5.4.1 it outputs the following, correctly deduplicating the extra `c` column
```
{ a: 'd', b: 'd', c: 'e', c_1: 'e' }
{ a: 'd', b: 'f', c: 'f', c_1: 'g' }
Parsing complete
```

In 5.5.1 it outputs the following, incorrectly deduplicating the `d`, `e`, and `f` in the data

```
Duplicate headers found and renamed.
Duplicate headers found and renamed.
{ a: 'd', b: 'd_1', c: 'e', c_1: 'e_1' }
Duplicate headers found and renamed.
{ a: 'd', b: 'f', c: 'f_1', c_1: 'g' }
Parsing complete
```
