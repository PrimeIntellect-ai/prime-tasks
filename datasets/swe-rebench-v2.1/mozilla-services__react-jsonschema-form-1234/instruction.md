File object becomes a basic js object
### Description
When we use the From component in a wrapper component and pass formData via props., the Form component transforms Props to State in `componentWillReceiveProps ` . Problem is when we use a custom widget with an input file, the `File` object is transformed to a basic object in [mergeObjects function](https://github.com/mozilla-services/react-jsonschema-form/blob/master/src/utils.js#L242) because the  `File` object is detected as an object.

I guess the solution is to [HIDDEN]

Do you think it's the way to go? I don't see any exception than `File` object which could be bad detected.

### Steps to Reproduce

1. Open https://codesandbox.io/s/n4mlxwq3ml
2. Open the browser console
3. Choose a file
4. See in the console onChange event is triggered twice and the File object changes.

#### Expected behavior
The File object stays a File object

#### Actual behavior

The File object becomes a basic js object

### Version

1.3.0

### Additional contract requirements

- A `File` value in `formData` must remain a `File` object, rather than becoming a plain JavaScript object, when `Form` updates its state from props.
