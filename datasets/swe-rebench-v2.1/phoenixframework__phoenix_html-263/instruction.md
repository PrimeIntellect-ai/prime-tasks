`inputs_for` option to not automatically generate the id field
Currently a structure like the following is not possible using `inputs_for` because the hidden id input is always added as sibling to the user defined markup. Maybe the markup for the id input could optionally be supplied to the callback, so the user can place it somewhere.

```eex
<ol>
  <%= inputs_for f, :fields, fn finner -> %>
    <li>[…]</li>
  <% end %>
</ol>
```

```html
<ol>
  <input type="hidden" …>
  <li>[…]</li>

  <input type="hidden" …>
  <li>[…]</li>

  <input type="hidden" …>
  <li>[…]</li>
</ol>
```

### Additional contract requirements

Nested forms continue to render available hidden fields by default. Callers may pass `skip_hidden: true` to `inputs_for` to suppress those automatic hidden inputs while still rendering the nested form content.
