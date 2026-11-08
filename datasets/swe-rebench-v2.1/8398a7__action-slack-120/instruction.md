Validate SLACK_WEBHOOK_URL
**Is your feature request related to a problem? Please describe.**

Say, a user made a typo like:

```
SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK.URL }}
```

the value of `SLACK_WEBHOOK_URL` would be `null`. This results in an obscure error like:

```
Cannot read property 'replace' of null
```

**Describe the solution you'd like**

Validate that `SLACK_WEBHOOK_URL` must be a string.

**Describe alternatives you've considered**

N/A

**Additional context**

N/A

### Additional contract requirements

- Constructing the client with a webhook URL that is `undefined`, `null`, or an empty string throws an error.
- A non-empty string webhook URL is accepted and yields a working client.
