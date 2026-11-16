[BUG] calling refresh without defining a type/key results in unhandled error
### Is there an existing issue for this?

- [X] I have searched the existing issues

### Current Behavior

![image](https://github.com/user-attachments/assets/180f6c7a-05a0-4ff5-a2d8-61faf14c51c0)
when refresh is called without defining a type, this error appears

### Expected Behavior

it should simply state that type is missing, similar to when keys are missing

### Steps To Reproduce

1. Go to '...'
2. Click on '....'
3. Run '...'
4. See error...


### Version

7.6.1

### Environment

- OS:
- Node:
- npm:


### Participation

- [X] I am willing to submit a pull request for this issue.

### Additional comments

_No response_

### Additional contract requirements

- `refresh` is a public static method of the `Mcdev` class exported from `lib/index.js`, with the signature `refresh(businessUnit, selectedTypes, keys)`.
- `refresh` returns a promise that resolves to an object of shape `{ [businessUnit: string]: { [type: string]: string[] } }`.
- When `selectedTypes` is `null`, `refresh` sets `process.exitCode` to `1`, resolves to an empty object, and performs no API calls.
