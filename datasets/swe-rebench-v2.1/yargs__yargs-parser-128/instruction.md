Disabling "flatten-duplicate-arrays" leads to unexpected results
Calling this example code:
```javascript
const yargsParser = require('yargs-parser');

const argv = yargsParser(process.argv.slice(2), {
	array: ['arr'],
	configuration: {
		'flatten-duplicate-arrays': false,
	},
});

console.log(JSON.stringify(argv, null, 2));
```
with these arguments:

`node example.js --arr One Two Three --arr Four Five Six --arr Seven Eight Nine --arr Ten Eleven Twelve`

I would expect the following output:
```json
{
  "_": [],
  "arr": [
    [
      "One",
      "Two",
      "Three"
    ],
    [
      "Four",
      "Five",
      "Six"
    ],
    [
      "Seven",
      "Eight",
      "Nine"
    ],
    [
      "Ten",
      "Eleven",
      "Twelve"
    ]
  ]
}
```
However, instead I get this output:
```json
{
  "_": [],
  "arr": [
    [
      [
        [
          "One",
          "Two",
          "Three"
        ],
        [
          "Four",
          "Five",
          "Six"
        ]
      ],
      [
        "Seven",
        "Eight",
        "Nine"
      ]
    ],
    [
      "Ten",
      "Eleven",
      "Twelve"
    ]
  ]
}
```

This doesn't seem right to me. Is this the expected behaviour? (If so, it is not apparent from the documentation, in my opinion.)
