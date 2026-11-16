🐛 Bug: Re-run command suggestion includes unnecessary --directory
### Bug Report Checklist

- [X] I have tried restarting my IDE and the issue persists.
- [X] I have pulled the latest `main` branch of the repository.
- [X] I have [searched for related issues](https://github.com/JoshuaKGoldberg/create-typescript-app/issues?q=is%3Aissue) and found none that matched my issue.

### Expected

I ran `npx create-typescript-app --mode create --base everything` and filled in all the options. At the end, it should have suggested a re-run command that:

* Included `--base everything` and `--mode create`
* Filled in values I provided in the prompt...
* ...and _not_ values implied by `--base everything` or `--mode create`



### Actual

This was the suggestion it printed:

```plaintext
●  Tip: to run again with the same input values, use: npx create-typescript-app --mode create --base everything --access public --description "Hooray. Delete." --directory delete-me-please --email-github git@joshuakgoldberg.com --email-npm npm@joshuakgoldberg.com --mode create --owner JoshuaKGoldberg --repository delete-me-please --title "Delete Me Please"
```

Note the `--directory delete-me-please`. That's implied by `--repository delete-me-please`. There's no need to print `--directory` if it's got the same value as `--repository`. Bug!

### Additional Info

_No response_

### Additional contract requirements

A re-run suggestion must retain the selected base and mode, along with values supplied by the user. It must omit option values already implied by the selected base or mode. In particular, it must omit the directory when create mode uses the repository name as the directory, and when initialize mode uses `.` as the directory; a user-supplied directory that is not implied must remain in the suggestion.
