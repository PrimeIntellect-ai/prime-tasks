The IdAttributePlugin can create conflicts
### Operating system

macOS Sonoma 14.6.1

### Eleventy

3.0.0-beta.1

### Describe the bug

The plugin does not check for existing `id` attributes in the markup, only ones created for headers previously. That means the following markup (from a real example):

```html
<section id="thank-you">
  <h2>Thank you!</h2>
  <p>…</p>
</section>
```

Will output

```html
<section id="thank-you">
  <h2 id="thank-you">Thank you!</h2>
  <p>…</p>
</section>
```


### Reproduction steps

1. Go to '...'
2. Click on '....'
3. Scroll down to '....'
4. See an error


### Expected behavior

_No response_

### Reproduction URL

_No response_

### Screenshots

_No response_

### Additional contract requirements

- Preserve IDs authored in the markup. If a generated heading ID would collide with an authored ID, assign the heading a distinct ID instead; generated IDs must also be unique among themselves.
