When not specifying port for Postgres DB port is defaulting to 0
## Summary

It looks like since the changes in https://github.com/argoproj/argo/pull/4307 if you do not specify a port for your PG configuration it will now default to `0` since the port type has changed to an integer and the concatenation logic will append `:0` to the connection string.

---

Impacted by this bug? Give it a 👍. We prioritise the issues with the most 👍.
