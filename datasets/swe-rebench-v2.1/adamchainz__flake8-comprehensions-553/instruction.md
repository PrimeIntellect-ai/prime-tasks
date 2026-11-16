Feature Request: Detect dictionary comprehensions with constant values
### Description

Hi! Thanks for this helpful tool.

I'm working with code that has a lot of

```python
{elt: None for elt in foo}
```

which is slower and (IMO) harder to read than

```python
dict.fromkeys(foo)
```

Would there be interest in a rule that checks for dictionary comprehensions with constant values?

This has rule has been accepted by [another project](https://github.com/astral-sh/ruff/issues/9592) and it was suggested to me that I create an issue here too.

### Additional contract requirements

- For a violation, report the diagnostic message exactly as `C420 Unnecessary dict comprehension - rewrite using dict.fromkeys().`
