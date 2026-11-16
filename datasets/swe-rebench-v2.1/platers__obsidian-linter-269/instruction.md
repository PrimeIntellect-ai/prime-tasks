FR: Obsidian Comment %% Has Empty Lines Added Around It
I have the following section:

```
%%
due-date:: [[2022-06-10]]
%%
```

which gets linted as follows -- the result is not expected or wanted:

```
%%

due-date:: [[2022-06-10]]

%%
```

It would be great if ` Linter ` would respect the comments' styling.

Thank you for considering.
