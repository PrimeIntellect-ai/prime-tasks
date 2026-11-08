Boolean checkbox can't send false
### Prerequisites
- [ x] I have read the [documentation](https://github.com/mozilla-services/react-jsonschema-form/blob/master/README.md#readme).
### Description

Boolean checkbox's require you to tick the box, you cannot send a false.
### Steps to Reproduce

Create a  form where a boolean field is required
#### Expected behavior

Either a unticked / ticked state will be accepted
#### Actual behavior

Only a ticked box is accepted.

I'm using a jsonschema-form to send a  json to an api that uses https://github.com/geraintluff/tv4 as a validator using the same schema.  tv4's interpretation of a required boolean is it can be true or false as long as it is present.  Which implementation is right?
### Version

^0.38.0
