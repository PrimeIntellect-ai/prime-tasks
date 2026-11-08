[Bug]: Custom GuardRail not Working
### What happened?

I've upgraded my LiteLLM from version 1.68 to 1.70.0 and I had to rollback. All my custom guardrails stopped working, even though they are on the config file, they are not shown in the UI. I've checked the documentation and I noticed that stuff changed for guardrails, but there is nothing about custom guardrails (the doc is the same - they are under the `guardrails` tag in the config file, not under `litellm_settings` > `guardrails`). Did something change?

### Relevant log output

```shell

```

### Are you a ML Ops Team?

No

### What LiteLLM version are you on ?

1.70.0

### Twitter / LinkedIn details

_No response_

### Additional contract requirements

- Custom guardrails declared under `guardrails` in the proxy configuration must continue to execute their configured behavior when their configured event occurs for an applicable request.
- Guardrails declared in the proxy configuration must appear in the guardrail UI listing alongside database-defined guardrails, and users must be able to open their details.
