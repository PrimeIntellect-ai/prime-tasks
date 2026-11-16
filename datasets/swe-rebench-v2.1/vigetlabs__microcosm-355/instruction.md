Ability to set history length externally
For the dev tools, I want to allow a user to not have to worry about adding `maxHistory: Infinity` when in development mode. It would be great if there was a way to adjust the settings of the history object externally, like:

```
repo.history.setLimit(Infinity)
```
