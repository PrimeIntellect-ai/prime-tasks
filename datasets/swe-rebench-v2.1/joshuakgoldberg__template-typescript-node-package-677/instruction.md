🚀 Feature: If the user running initialize isn't already in allcontributors, add them
### Bug Report Checklist

- [X] I have tried restarting my IDE and the issue persists.
- [X] I have pulled the latest `main` branch of the repository.
- [X] I have [searched for related issues](https://github.com/JoshuaKGoldberg/template-typescript-node-package/issues?q=is%3Aissue) and found none that matched my issue.

### Overview

Right now, `addOwnerAsContributor` wipes out the `.all-contributorsrc` contributors _except_ for `"JoshuaKGoldberg"` and the currently running user. But what if that user isn't yet in the contributors list? They should be added for `"tool"` if so.

### Additional Info

_No response_
