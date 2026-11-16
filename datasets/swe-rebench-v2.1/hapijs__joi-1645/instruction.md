Allow self references
<!--
  ⚠️ ⚠️ ⚠️ ⚠️ ⚠️ ⚠️
  REMOVING, MISUSING OR NOT FILLING THIS TEMPLATE IS A GREAT ENCOURAGEMENT FOR MAINTAINERS TO CLOSE THE ISSUE, IF YOU DON'T RESPECT OUR TIME DON'T EXPECT US TO RESPECT YOURS
  ⚠️ ⚠️ ⚠️ ⚠️ ⚠️ ⚠️
-->

#### Describe the problem you are trying to fix (provide as much context as possible)
I use a `success` boolean key in message responses, and the structure of the message often depends on if it is true or false. I use `Joi.alternatives` to match on `true` or `false` but the syntax is pretty awkward and confusing for new readers (especially `unknown()`):
```javascript
responseSchema: Joi.object({
	messageId: Joi.number(),
    success: Joi.boolean(),
).when(Joi.object({ success: true }).unknown(), {
	then: Joi.object({
		responseObject: Joi.object(),
		otherData: Joi.string(),
		isDataNew: Joi.boolean(),
	}),
	otherwise: Joi.object({
		reason: Joi.string().valid(Object.values(Constants.FailureReasons)),
		description: Joi.string().optional(),
	}),
}),
```

The line I think is strange is this one:
```javascript
).when(Joi.object({ success: true }).unknown(), {
```

#### Which API (or modification of the current API) do you suggest to solve that problem ?
I would prefer a syntax that supported this case more easily and clearly.
I am not sure what the ideal solution would be, but maybe something like this would work:
```javascript
responseSchema: Joi.object({
	messageId: Joi.number(),
    success: Joi.boolean().case({
        true: Joi.object({
		    responseObject: Joi.object(),
		    otherData: Joi.string(),
		    isDataNew: Joi.boolean(),
	    }),
        false: Joi.object({
		    reason: Joi.string().valid(Object.values(Constants.FailureReasons)),
		    description: Joi.string().optional(),
	    }),
    }),
),
```

#### Are you ready to work on a pull request if your suggestion is accepted ?
Honestly I am not sure I have the depth of understanding required to contribute to this project yet, I am just getting into it.

### Additional contract requirements

A conditional schema must be able to inspect a property of the value being validated. `Joi.ref(path, { self: true })` is a supported way to make the reference resolve against that value rather than a sibling value.
