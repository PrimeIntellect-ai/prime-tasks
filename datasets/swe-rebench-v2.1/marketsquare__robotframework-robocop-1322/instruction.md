Enable all rules at once
We have growing number of non-default rules. User may want to enable all rules and then disable unwanted ones, rather than keeping track if new release contain new rules etc.

We could reuse ruff syntax:

```
select = ["ALL"]
```
