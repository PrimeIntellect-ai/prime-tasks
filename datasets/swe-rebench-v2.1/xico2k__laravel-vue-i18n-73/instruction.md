Feature request: Language array
Hi,

I'm not sure if this is already possible, but can there be a function which allows you to use an array of language strings.

I for example have in my `en.php`

```php
<?php

return [
    'homepage' => [
        'title' => 'This is the homepage',
        'content' => [
            'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nam convallis vitae est vitae posuere. Quisque imperdiet nunc nisi, ut imperdiet lectus auctor eu. Donec elit neque, dignissim eu tempor placerat, volutpat sed odio. Praesent non ligula odio. Curabitur finibus est quis urna sagittis, a finibus nulla lobortis. Phasellus sit amet ligula non urna congue elementum id vitae eros. Ut faucibus cursus finibus. Sed pretium at tortor ac semper. Morbi quis est quis ligula maximus mollis at non est. Aenean tempor metus mattis quam pretium suscipit. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia curae.',
            'Duis ultrices elementum nulla, et posuere velit eleifend eget. Donec vitae malesuada neque. Curabitur ac ipsum at risus consectetur mattis. Nam id ipsum quis velit dignissim venenatis. Pellentesque vulputate semper leo eu aliquet. Vestibulum ornare nunc neque, non vulputate nulla tempus eget. Donec in turpis sed turpis facilisis consectetur at tristique odio. In non congue augue, sit amet posuere quam. Cras pulvinar leo posuere lectus aliquet cursus. Vivamus metus ligula, scelerisque in finibus quis, elementum et urna. Pellentesque purus lorem, imperdiet et pulvinar quis, dapibus id nisi. Sed varius orci id arcu mollis tempor. Donec vitae pretium urna. Integer egestas ipsum et tempus euismod.',
        ],
    ]
];
```

In the Json this gets converted to.
```json
{
	"pages.homepage.title": "This is the homepage",
	"pages.homepage.content.0": "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nam convallis vitae est vitae posuere. Quisque imperdiet nunc nisi, ut imperdiet lectus auctor eu. Donec elit neque, dignissim eu tempor placerat, volutpat sed odio. Praesent non ligula odio. Curabitur finibus est quis urna sagittis, a finibus nulla lobortis. Phasellus sit amet ligula non urna congue elementum id vitae eros. Ut faucibus cursus finibus. Sed pretium at tortor ac semper. Morbi quis est quis ligula maximus mollis at non est. Aenean tempor metus mattis quam pretium suscipit. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia curae.",
	"pages.homepage.content.1": "Duis ultrices elementum nulla, et posuere velit eleifend eget. Donec vitae malesuada neque. Curabitur ac ipsum at risus consectetur mattis. Nam id ipsum quis velit dignissim venenatis. Pellentesque vulputate semper leo eu aliquet. Vestibulum ornare nunc neque, non vulputate nulla tempus eget. Donec in turpis sed turpis facilisis consectetur at tristique odio. In non congue augue, sit amet posuere quam. Cras pulvinar leo posuere lectus aliquet cursus. Vivamus metus ligula, scelerisque in finibus quis, elementum et urna. Pellentesque purus lorem, imperdiet et pulvinar quis, dapibus id nisi. Sed varius orci id arcu mollis tempor. Donec vitae pretium urna. Integer egestas ipsum et tempus euismod.",
}
```

Now I'm not sure how to retrieve these language strings from the array.
The reason I want to do it like this, is because I want them to be seperate paragraphs.
Each line is supposed to be a ```<p></p>```

So preferably I would do something like:

```vue
<p v-for="line in $t('pages.homepage.content')">
    {{line}}
</p>
```

But this just outputs.
```html
   <p>p</p>
   <p>a</p>
   <p>g</p>
   <p>e</p>
   <p>s</p>
   <p>.</p>
   <p>h</p>
   <p>o</p>
   <p>m</p>
   <p>e</p>
   <p>p</p>
   <p>a</p>
   <p>g</p>
   <p>e</p>
   <p>.</p>
   <p>c</p>
   <p>o</p>
   <p>n</p>
   <p>t</p>
   <p>e</p>
   <p>n</p>
   <p>t</p>
```

Is there a 'simple' fix for this?
Or could there maybe be a seperate function that can work for multiline/arrays like that. (E.g: $tm() )

### Additional contract requirements

- The `$t` translation function available on Vue component instances (e.g. `this.$t` or the `$t` template mixin) accepts a translation key and an optional replacements map. For a simple key it returns the translated string. When the underlying messages contain indexed child entries for the key (`key.0`, `key.1`, …), it returns an array of those child values ordered by their index, suitable for `v-for` iteration. The returned array is reactive: mutating it updates the rendered output.
- The library's public API exports a `trans(key, replacements?)` helper (e.g. `import { trans } from 'laravel-vue-i18n'`) that mirrors `$t`: it returns the translated string for a simple key, or a plain JavaScript array of the indexed child values (ordered by index) when the key has indexed child entries.
