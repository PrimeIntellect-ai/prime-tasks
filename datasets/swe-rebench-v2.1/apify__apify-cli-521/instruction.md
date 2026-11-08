Subcommands not to be separated by `:` but space instead
Based on the Apify Actors specification, the sub-commands should not be separated by `:` as:

```
apify secrets:add
apify actor:get-input
```

But by the space instead:

```
apify secrets add
apify actor get-input
```

This is a breaking change mainly for the secrets, as actor sub-commands are not used much. With this, we should consider if there is anything we should improve with the `apify secrets` command to beware of more breaking changes in the future.
