UnusedUnaryOperator>aliases' is misspelled or does not exist
Version of detekt used: da8b164c5da3a2c8017452355c1754df7344c8a7

It seems that if a rule does not have the `@Alias` annotation (like `UnusedUnaryOperator`) then putting the `alias` property in the configuration file for it leads to an error:

```log
Property 'potential-bugs>UnusedUnaryOperator>aliases' is misspelled or does not exist. This error may also indicate a detekt plugin is necessary to handle the 'potential-bugs>UnusedUnaryOperator>aliases' key.
```
