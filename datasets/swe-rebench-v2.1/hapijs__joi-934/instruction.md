Extended Joi does not contain certain top-level functions
#### Context

* *node version*: 4.2.3
* *joi version*: 9.0.0-6
* *environment* (node, browser): node
* *used with* (hapi, standalone, ...): standalone
* *any other relevant information*:

#### What are you trying to achieve or the steps to reproduce ?

1. Extend Joi using `joi.extend`. See example below
1. Top-level functions like `.when` and `.disallow` do not exist

[HIDDEN]

**example**
```js
const Custom = Joi.extend({
  name: 'newType'
})
console.log(Custom.when) // undefined
```

#### Which result you had ?

The new type exists on the extended Joi, but the top-level functions like `Joi.when` and `Joi.disallow` do not exist.

#### What did you expect ?

I expected those functions to exist.

### Additional contract requirements

- `Joi.extend(extensions)` returns a new Joi instance that is an `instanceof Any`, where `Any` is the base schema class exported from `lib/any`.
- An extended Joi instance exposes the top-level `when` and `disallow` functions, and those functions can produce Joi schemas.
