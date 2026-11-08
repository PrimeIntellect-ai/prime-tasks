Unexpected trimming of whitespace after loop
Given a template like this:

```hbs
{{#each routes}}
import { default as {{this.handler}} } from '{{this.file_path}}'
{{/each}}

addEventListener('fetch', (event) => {
  event.respondWith(handleEvent(event))
})
```

handlebars 4.1.3 will remove the empty line after the loop (in fact, it will remove all empty lines if there are any):

```js
import { default as __hello_handler } from './hello.js'
import { default as __world_index_handler } from './world/index.js'
import { default as __index_handler } from './index.js'
addEventListener('fetch', (event) => {
  event.respondWith(handleEvent(event))
})
```

I'm wondering why that happens though? I don't use `~` or anything else that controls whitespace. My understanding is that rendering should not change any non-templating bits.

### Additional contract requirements

When a loop block is followed by multiple blank lines in the template, rendering must preserve those source blank lines rather than collapsing them to a single blank line.
