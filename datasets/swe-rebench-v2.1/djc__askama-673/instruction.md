Trim all but 1 whitespace jinja condition
@vallentin suggested [here](https://github.com/djc/askama/pull/664#pullrequestreview-945253861) that we could extend the "trim_all_whitespace" feature to be able to trim all whitespace characters but one.

So currently, we have:

```jinja
<div>    {%- if foo -%} blabla {%- endif -%} </div>
```

Which will remove all whitespace characters before and after (by using `-`) and we have:

```jinja
<div>    {%+ if foo +%} blabla {%+ endif +%} </div>
```

Which means that the whitespace should be saved (only useful when the "trim all whitespace" feature is enabled).

The idea would now to add a new character to strip all whitespace characters but one. I propose `~`:

```jinja
<div>    {%~ if foo %} blabla {% endif %} </div>
```

### Additional contract requirements

- When `~` trims a whitespace run containing a newline, the retained character must be a newline.
