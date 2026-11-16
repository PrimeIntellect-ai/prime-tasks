`link-to` with conditional model is not converted correctly
Before:
```hbs
{{link-to (t "show") "user" (if linkActor event.actor.id event.user.id)}}
```

Expected:
```hbs
<LinkTo @route="user" @model={{if linkActor event.actor.id event.user.id}}>{{t "show"}}</LinkTo>
```

Actual:
```hbs
<LinkTo @route="user" @query={{hash}}>{{t "show"}}</LinkTo>
```

### Additional contract requirements

- For both block and inline `link-to` calls with route `"user"`, models `this.first` and `this.second`, emit `<LinkTo @route="user" @models={{array this.first this.second}}>Show</LinkTo>`. When the call also has `(query-params foo="baz")`, emit `<LinkTo @route="user" @models={{array this.first this.second}} @query={{hash foo="baz"}}>Show</LinkTo>`.
