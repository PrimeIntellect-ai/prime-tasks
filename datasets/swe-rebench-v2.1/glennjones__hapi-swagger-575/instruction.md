invalid swagger generated for Joi.date().min(Joi.ref('reference'))
#### Context

* *hapi-swagger version*: 7.7.0

#### What are you trying to achieve or the steps to reproduce ?
I would like to use Joi to validate that an end date is greater than a start date.
The validation works fine, but the swagger that hapi-swagger generates is invalid.

```js
start: Joi.date(),
end: Joi.date().min(Joi.ref('start')),
```

#### What result did you get?
Validation works fine, but hapi-swagger generates :
```js
"start":{"type":"string","format":"date"}
"end":{"type":"string","format":"date","minLength":"ref:start"}
```
But this is invalid.  Using http://editor.swagger.io/, I get this error message.
```js
"code":"INVALID_TYPE","params":["integer","string"],"message":"Expected type integer but found type string"
```

#### What did you expect ?
I expected to have a valid swagger

### Additional contract requirements

- For Joi.date() properties with .min() and/or .max() bounds, the generated property schema must be exactly { 'type': 'string', 'format': 'date' }, with no bound keywords. This applies to literal date bounds, 'now', and Joi.ref(...) bounds.
