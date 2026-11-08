`if` statement with parens fails to parse
The following fails to parse with tera but works fine with jinja2:

```
{% if (brand.id == "barfoo") or (brand.id == "foobar") %}LOL{% endif %}
```
with the following error:
```
Tera error: Error { kind: Msg("Failed to parse 'test.html'"), source: Some(Error { kind: Msg(" --> 1:17\n  |\n1 | {% if (brand.id == \"barfoo\") or (brand.id == \"foobar\") %}LOL{% endif %}\n  |                 ^---\n  |\n  = expected `+`, `-`, `*`, `/`, or `%`"), source: None }) }
```

Changing the template to something more reasonable also fails with the exact same error:
```
{% if (brand.id == "barfoo" or brand.id == "foobar") %}LOL{% endif %}
```

I know the first example is a bit silly and you're not aiming for 100% jinja compatibility but do you think this could be fixed?

Thanks in advance!
