Support for toJSON
I'd like to have a little different model structure internally in my app than returning it externally via API. Unfortunately, using `fastify` and `fast-json-stringify` this can't be done as `fast-json-stringify` does not use the objects `toJSON` function to map the data somehow.

I guess it could be on purpose to improve the performance, but this is a little bit unintuitive to do:

`reply.send(model.toJSON());`

and what even worse:

```js
const models = [arrayOfModels];
reply.send(models.map(model => model.toJSON()));
```

This doesn't make much sense as there's no difference if I have to do this manually or if it would be done by `fast-json-stringify` - just as I'd expect.

Here's a little reproduction:

```js
const fastJson = require("fast-json-stringify");

const stringify = fastJson({
    type: "object",
    properties: {
        groups: {
            type: "array",
            items: {
                type: "string"
            }
        }
    }
});

class User {
    constructor() {
        this.groups = [{ name: "admin" }, { name: "subscriber" }];
    }

    toJSON() {
        return {
            ...this,
            groups: this.groups.map(group => group.name)
        };
    }
}

const user = new User();

console.log(stringify(user)); // returns: {"groups":["[object Object]","[object Object]"]}
console.log(JSON.stringify(user)); // returns: {"groups":["admin","subscriber"]}
```

Could you somehow relate to this issue? And maybe you have some idea for a solution in `fastify`?
