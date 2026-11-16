Is it possible to have a newline inside `fail` function?
Is it possible to have a newline inside `fail` function?

`{{- fail "fail" }}` gives:
```
Error: execution error at (panel/templates/_helpers.tpl:17:4): fail
```

whereas `{{- fail "\nfail" }}` gives:
```
Error: template: panel/templates/_helpers.tpl:17:4: executing "panel.api.image" at <fail "\nfail">: error calling fail: HELM_ERR_START
failHELM_ERR_END
```
So adding a newline (`\n`) inside `fail` function causes `fail` function to fail.

Is it another way to add a newline to the fail function or is it impossible?
