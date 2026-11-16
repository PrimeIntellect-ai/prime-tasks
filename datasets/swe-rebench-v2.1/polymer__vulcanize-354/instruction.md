Imports inside of templates are incorrectly processed
Given a construction of
```html
<template>
<link rel="import" href="foo.html">
</template>
```
Vulcanize will incorrectly inline or remove `foo.html`.
