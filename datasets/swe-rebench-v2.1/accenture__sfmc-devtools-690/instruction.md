[BUG] error during retrieve of interaction fails entire download
### Is there an existing issue for this?

- [X] I have searched the existing issues

### Current Behavior

if any api error occurs due to a single interaction, no interactions are stored at all.

### Expected Behavior

problems should be logged and the faulty records should then be skipped

### Steps To Reproduce

_No response_

### Version

4.3.0

### Environment

_No response_

### Participation

- [X] I am willing to submit a pull request for this issue.

### Additional comments

_No response_

### Additional contract requirements

- When an interaction cannot be retrieved, the problem is logged and the log entry identifies the affected interaction by its key, name, or id.
