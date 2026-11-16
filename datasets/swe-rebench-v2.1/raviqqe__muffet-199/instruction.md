Wrong handling of multi-url srcset
Muffet finds 1 link instead of 3 in the following HTML:

```html
<picture>
  <source type="image/webp" srcset="images/1-300w.webp 300w, images/1-600w.webp 600w, images/1-1200w.webp 1200w">
</picture
```

For example, for `http://localhost` would be `http://localhost/images/1-300w.webp 300w, images/1-600w.webp 600w, images/1-1200w.webp 1200w` URL that always fails with 404 error
