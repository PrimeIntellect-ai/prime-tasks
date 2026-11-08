Can't disable a plugin
If you create a plugin for ember-template-lint and then try to disable it, this won't work, for the following reasons:

1. if you disable only the rule that is associated with a plugin, the code here: https://github.com/rwjblue/ember-template-lint/blob/master/lib/rules/base.js#L72 will error out because plugins are not recognized as rules (only the rules that ship with `ember-template-lint` are recognized as rules.
2. If you disable all rules, the plugin's configuration does not seem to change in time for it to process the directive. I tried to log the events that were happening and their sequence, and this is what I found:

```
(output from the plugin, in its visitor() method, logging its config:)
this.config { min: 20, max: 100 }
-> rules/base.js, line 401 (https://github.com/rwjblue/ember-template-lint/blob/master/lib/rules/base.js#L401)
-> rules/base.js line 413 (https://github.com/rwjblue/ember-template-lint/blob/master/lib/rules/base.js#L401)
-> returning { tree: false, value: false }
-> rules/base.js line 337 (https://github.com/rwjblue/ember-template-lint/blob/master/lib/rules/base.js#L337)

/Users/psbanka/dev/copy-tango/app/pods/support/docs-search/template.hbs
  -:-  error  Template length of 12 is smaller than 20  length-validation
```

For some reason the pugins seem to be processed *before* instructions are processed and therefore their configs do not get updated.

### Additional contract requirements

An inline disable directive naming a plugin-provided rule must suppress that rule's reported violation. An inline disable directive with no rule names must also suppress violations from plugin-provided rules while the template is being processed.
