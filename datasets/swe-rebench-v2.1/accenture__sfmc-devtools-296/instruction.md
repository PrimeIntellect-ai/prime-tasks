[BUG] dataExtension fields not properly formatted after de-CREATE
### Is there an existing issue for this?

- [X] I have searched the existing issues

### Current Behavior

[HIDDEN]

during CREATE however, we take what was deployed (including fields only required for the API call) and save that directly into the retrieve folder without further processing

### Expected Behavior

fields are always run through [HIDDEN]

### Steps To Reproduce

_No response_

### Version

3.1.3

### Environment

- OS:
- Node:
- npm:


### Participation

- [X] I am willing to submit a pull request for this issue.

### Additional comments

_No response_

### Additional contract requirements

- On CREATE, format data-extension fields before saving them to the retrieve folder, consistently with the field formatting applied after retrieval.
