computed link-to target route is removed
I just tried this codemod and it seems to run great.

I've found one issue though:

```hbs
        {{#link-to (concat settingsRoute ".profile") class="settings-nav-item"}}
          <div class="settings-nav-item__title">{{t "settings.profile.title"}}</div>
        {{/link-to}}
```

was transformed to:

```html
<LinkTo @route="" class="settings-nav-item">
          <div class="settings-nav-item__title">
            {{t "settings.profile.title"}}
          </div>
</LinkTo>
```

`concat` wasn't part of the codemod configuration helpers array.

### Additional contract requirements

When a `link-to` target is a computed expression, the converted `LinkTo` component must retain that expression as its route value rather than produce an empty route.
