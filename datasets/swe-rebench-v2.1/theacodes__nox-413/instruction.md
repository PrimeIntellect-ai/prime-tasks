Exclude combinations from parametrized matrix builds
I'm using the `@parametrize` decorator to create a build matrix, but i've got certain combinations I wish to exclude.

right now i'm using a little escape hatch

```python
if valid_combination(*deps):
    run_tests(session, *deps)
else:
    session.skip("unsupported combination")
```

would be nice if Nox could provide an API for adding or removing 'cells' from the matrix (similarly to what you can do with github actions)

### Additional contract requirements

When a parametrized session includes a parameter named `python`, its value selects that session's Python interpreter if the session function does not declare a `python` argument. If the function declares a `python` argument, the value is passed to it as a normal parameter instead of selecting the interpreter. Explicitly provided matrix combinations are the combinations that become sessions; an omitted combination must not be generated or run.
