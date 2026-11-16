Static file urls not correct
When rendering the asset url, it appears as

```html
<script src="/static/bird/button.js"></script>
```

But the location on the filesystem is actually `/static/django_bird/bird/button.js`. There's a disconnect here between the storage prefix (`django_bird`) and the url provided by the `Asset`.
