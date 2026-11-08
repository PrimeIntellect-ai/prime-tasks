Pages with globals don't generate properly
Here's the input

```html
<import layout from='layouts/base.html' />

<layout>
  <h1 class="{website.dummy}">{ website.dummy  || 'hello'}</h1>
</layout>
```

```html
<!DOCTYPE html>
<html lang="en">

<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Document</title>
</head>

<body>
  <h1>Layout {globals.website.dummy}</h1>

  <slot />
</body>

</html>
```

Here's the compilation file:

```js
const fs = require('fs-extra');
const { compile, escape } = require('pure-engine')

async function example() {
  const content = await fs.readFile('website/pages/about.html', 'utf-8')
  const { template, warnings, errors } = await compile(content, { cache: false, paths: ['website/pages', 'website/components'] })
  console.log(template({ website: { dummy: 'baz' } }, escape))
	console.log(warnings);
	console.log(errors);


}

example()
```

The layout is not generated and I'm getting the following error:

```
Cannot read property 'reduce' of undefined
at complexReplace (/Users/zaiste/Workspace/pure-playground/node_modules/abstract-syntax-tree/src/replace.js:12:31)
```
