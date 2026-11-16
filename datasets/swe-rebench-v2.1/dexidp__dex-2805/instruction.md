Skip redirection to approval when it's not required
### Preflight Checklist

- [X] I agree to follow the [Code of Conduct](https://github.com/dexidp/dex/blob/master/.github/CODE_OF_CONDUCT.md) that this project adheres to.
- [X] I have searched the [issue tracker](https://www.github.com/dexidp/dex/issues) for an issue that matches the one I want to file, without success.

### Problem Description

There is an unnecessary redirection to /approval when in fact it is not required by configuration.

### Proposed Solution

Skip the redirection and send the code directly back to the client.

### Alternatives Considered

_No response_

### Additional Information

_No response_
