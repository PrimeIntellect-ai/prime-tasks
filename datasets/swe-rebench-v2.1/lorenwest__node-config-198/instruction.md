Date type doesn't overwrite
I am having problems with Date type not being overwritten. I have prepared a repo to show the error.

https://github.com/axelhzf/node-config-error

The problem is a have a default.js

```js
module.exports = {
  str: "A",
  date: new Date(2015, 0, 1)
};
```

and a development.js

```js
module.exports = {
  str: "B",
  date: new Date(2015, 0, 2)
};
```

index.js

```js
var config = require("config");
console.log(config.get("str")); // B
console.log(config.get("date")); // Thu Jan 01 2015 00:00:00 GMT+0000 (WET) it should be Thu Jan 02 2015 00:00:00 GMT+0000 (WET)
```

The date property has the default value instead of development value
