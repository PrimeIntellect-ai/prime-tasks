link-to conversion drops params
Noticed while working on ember-api-docs, an example of this is here: https://github.com/ember-learn/ember-api-docs/pull/768/commits/3acc0d5fd868eb273c754402f0faa0dd0c553131#diff-86ff65401adf2a1a22505ed43fd38b01de6f9f5781bfbfb100d1e51c55c0d5e3L55

I'm not sure which of the "special cases" are necessary to trigger this but in our case the dynamic route, query-params present, and data-test hash pair are all present.

Input:
```hbs
{{#link-to (concat parentName ".index")
           model.project.id
           model.projectVersion.compactVersion
           model.name
           (query-params anchor=undefined)
           class="tabbed-layout__menu__item"
           activeClass="tabbed-layout__menu__item_selected"
           current-when=(concat parentName ".index")
           data-test-tab="index"
        }}
```

Broken output:

```hbs
<LinkTo @route={{concat parentName ".index" }} @models={{array model.project.id model.projectVersion.compactVersion}} @query={{hash anchor=undefined}} class="tabbed-layout__menu__item" @activeClass="tabbed-layout__menu__item_selected" @current-when={{concat parentName ".index"}} data-test-tab="index">
```

Notice that `model.name` is not in the array constructed for `@models`
