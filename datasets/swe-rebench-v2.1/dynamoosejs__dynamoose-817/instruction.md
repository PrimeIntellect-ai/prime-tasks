Creating a model with undefined attributes throws an error
```
const User = new Schema({
   age: Number,
   id: {
       type: String,
       hashKey: true,
   },
   name: String,
})
```

```
User.create({
   age: undefined,
   id: 1,
   name: "Tim",
});
```

Note: The undefined attribute has to be the first attribute of the object.

Error:
> Cannot convert undefined or null to object

Stacktrace:
> at Function.keys (<anonymous>) at isValid (/Users/mick/git/myproject/node_modules/dynamoose/lib/Document.js:46:24)

### Additional contract requirements

- `Model.isDynamoObject(object)` is a public static method that returns a boolean indicating whether `object` is a valid DynamoDB attribute representation. A property value inside `object` that is `undefined` or `null` makes the representation invalid, so the method returns `false` for such input.
