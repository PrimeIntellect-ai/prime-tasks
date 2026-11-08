coerceArray in dao.js also converts simple objects
<!--
- Please ask questions at https://groups.google.com/forum/#!forum/loopbackjs or
  https://gitter.im/strongloop/loopback

- Immediate support is available through our subscription plans, see
  https://strongloop.com/api-connect-faqs/
-->

### Bug or feature request

<!--
Mark your choice with an "x" (eg. [x], NOT [*]).
-->

- [x] Bug
- [ ] Feature request

### Description of feature (or steps to reproduce if bug)
When declaring a property in model definition JSON as simple object with the following declaration
```
"sampleProp": {
  "type": "object"
}
```
and create a model instance with this property empty or an empty object, it gets converted through [coerceArray](https://github.com/strongloop/loopback-datasource-juggler/blob/2.x-latest/lib/dao.js#L1540) into an empty **array**  property, while it should be an **Object**

[HIDDEN]

## **Messed up our whole test suites... Quite critical... Please fix ASAP!!!**

### Link to sample repo to reproduce issue (if bug)



### Expected result
It should save it in DB and interact with it as an empty Object


### Actual result (if bug)
It gets converted into an empty array by this function [coerceArray](https://github.com/strongloop/loopback-datasource-juggler/blob/2.x-latest/lib/dao.js#L1540)


### Additional information (Node.js version, LoopBack version, etc)
loopback-datasource-juggler version: 2.54.0

### Additional contract requirements

A saved model with an empty object-valued property must be findable by querying for that property with an empty object.
