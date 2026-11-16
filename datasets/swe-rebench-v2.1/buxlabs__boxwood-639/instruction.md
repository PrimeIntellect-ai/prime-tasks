<script>'s src not interpolated
In the following snippet the `src` attribute won't be interpolated:

```html
<script type="text/javascript" src="/{ website.javascript }" />
```

while this one works:

```html
<link rel="stylesheet" href="/{ website.stylesheet }">
```
