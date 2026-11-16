Multiple validators not working with objects
It seems like multiple validators are not working properly when they are objects.
Here is an example:

```
const field = {
    type: 'object',
    props: {
        type: {
            type: 'string',
            pattern: /^field$/
        },
        fieldId: {type: 'number', positive: true, integer: true},
        title: {type: 'string', min: 4, max: 50, optional: true},
        values: {
            type: 'array',
            items: {type: 'string', min: 1, max: 50}
        }
    }
};

const seperator = {
    type: 'object',
    props: {
        type: {
            type: 'string',
            pattern: /^seperator$/
        }
    }
};

const col = {
    type: "array",
    min: 1,
    max: 4,
    items: [
        field,
        seperator
    ],
};

const schema = {bla: col};
console.log(validator.validate({bla:[{"type": "sfdf"}]}, schema));
```

I expect this validation to fail, but it succeeds. It seems like it only checks whether the array contains an object, but does no further validation regarding the properties.

With other types than objects it is working properly, example:

```
const col = {
    type: "array",
    min: 1,
    max: 4,
    items: [
        {type: 'boolean'},
        {type: 'string', min: 5}
    ],
};

const schema = {bla: col};
console.log(validator.validate({bla:["sfdf"]}, schema));
```
Fails as expected because the string is to short.

And for a single validator, everything is working fine, too:

```
const col = {
    type: "array",
    min: 1,
    max: 4,
    items: field
};
```
