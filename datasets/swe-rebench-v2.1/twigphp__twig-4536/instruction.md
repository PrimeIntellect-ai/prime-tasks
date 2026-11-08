`types` tag "argument" is not a mapping
While working a bit with types, I realized that I don't like the way we declare types via the `types` tag:

 * In the docs, we say that `types` uses a mapping, which is not true:
   * Mappings don't support keys like `foo?`
   * Mappings support more than strings as values
   * Mappings support nesting
 * With that in mind, `{}` and `,` look more like noise to me as it makes the syntax more verbose for no good reasons
 * Less important, one might think that they could declare a mapping and use it as types: `{% type some_mapping_declared_with_set %}`

So, I'd like to get rid of this concept of a pseudo mapping.

For all tags, we're trying to have the "most possible readable syntax". This is highly subjective, but what about something more similar to what we're doing for other tags like:

```
{% types
    is_correct as 'boolean'
    score? as 'number'
%}
```

I'm not 100% confident that my proposal is the best one, but at least, it's a baseline for discussion.

/cc @drjayvee @ruudk

### Additional contract requirements

The `types` tag must accept type declarations without the enclosing `{}` braces. Each declaration has the form `name: 'type'`, and a `?` suffix on the name marks the variable as optional (`name?: 'type'`). Multiple declarations are separated by commas. The `{}`-enclosed form must keep working. For example, `{% types is_correct: 'boolean', score?: 'number' %}` declares `is_correct` as a non-optional `boolean` and `score` as an optional `number`.

/cc @drjayvee @ruudk
