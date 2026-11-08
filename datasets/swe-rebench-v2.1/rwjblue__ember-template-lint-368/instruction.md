Unused block params don't consider partials
Consider the following templates:

`app/templates/components/family-tree.hbs`
```hbs
<ul>
  {{#each _childViews as |childView|}}
    {{partial "partials/family-tree/tier"}}
  {{/each}}
</ul>
```

`app/templates/partials/family-tree/-tier.hbs`
```hbs
{{#if childView.isVisible}}
  <li>
    <h3>{{childView.name}}</h3>
    {{#if childView.childViews}}
      <ul>
        {{#each childView.childViews as |childView|}}
          {{partial "partials/family-tree/tier"}}
        {{/each}}
      </ul>
    {{/if}}
  </li>
{{/if}}
```

Here we're using a partial that relies on a variable existing in its parent scope, because using a component would have performance problems given the large size of the potential tree to be rendered.

The template linter will complain: `unused-block-params: 'childView' is defined but never used`. However, failing to define `childView` will cause the application not to work.

I'd love to discuss how the linter could be improved to infer that block params defined as an ancestor of a `partial` might indeed be used by that partial. Or possibly the linter could even read that partial and check if it's used in that file?
