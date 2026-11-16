Properties not parsed when using Tailwind height class
I managed to get a minimal example that happened to me while working with Tailwind CSS, but i guess it's more generic to any class that starts with `h-` prefix.

If i use Tailwind CSS `h-<number>` class on some elements that have other microformat classes like in this minimal example with u-logo and u-nickname:
```xml
<article class="h-card">
   <h1> TITLE </h1>
   <img class="h-36 photo u-logo"
          alt="An example alt title"
          src="https://example.com/img.png"
    />
    <p class="h-21 u-nickname"> John Doe </p>
</article>
```
The parser skips mf properties and produces :
```json
{
    "items": [
        {
            "type": [
                "h-card"
            ],
            "properties": {
                "name": [
                    "TITLE An example alt title\nJohn Doe"
                ]
            }
        }
    ],
    "rels": {},
    "rel-urls": {},
    "debug": {
        "package": "https://packagist.org/packages/mf2/mf2",
        "source": "https://github.com/indieweb/php-mf2",
        "version": "v0.5.0",
        "note": [
            "This output was generated from the php-mf2 library available at https://github.com/indieweb/php-mf2",
            "Please file any issues with the parser at https://github.com/indieweb/php-mf2/issues",
            "Using the Masterminds HTML5 parser"
        ]
    }
}
```

Instead, if I remove h-<number> classes, it's working as expected:

```xml
<article class="h-card">
   <h1> TITLE </h1>
   <img class="photo u-logo"
          alt="An example alt title"
          src="https://example.com/img.png"
    />
    <p class="u-nickname"> John Doe </p>
</article>
```
with output:
```json
{
    "items": [
        {
            "type": [
                "h-card"
            ],
            "properties": {
                "logo": [
                    {
                        "value": "https://example.com/img.png",
                        "alt": "An example alt title"
                    }
                ],
                "nickname": [
                    "John Doe"
                ],
                "name": [
                    "TITLE An example alt title\nJohn Doe"
                ]
            }
        }
    ],
    "rels": {},
    "rel-urls": {},
    "debug": {
        "package": "https://packagist.org/packages/mf2/mf2",
        "source": "https://github.com/indieweb/php-mf2",
        "version": "v0.5.0",
        "note": [
            "This output was generated from the php-mf2 library available at https://github.com/indieweb/php-mf2",
            "Please file any issues with the parser at https://github.com/indieweb/php-mf2/issues",
            "Using the Masterminds HTML5 parser"
        ]
    }
}
```

This scenario seems to work using the [Go implementation](https://go.microformats.io/)
properties with invalid names are not properly ignored
in `v0.5.0`, the following example (distilled down from https://catgirlin.space/ as of right now)

```html
<div class=" h-feed pt-2">
  <div class="p-4 h-entry">
    <a class="u-url" href="https://example.com/bar">bar </a>
  </div>
  <div class="p-4 h-entry">
    <a class="u-url" href="https://example.com/foo">foo</a>
  </div>
</div>
```

parses as
```json
{
    "items": [
        {
            "type": [ "h-feed"],
            "properties": [
                [
                    {
                        "type": ["h-entry" ],
                        "properties": {
                            "url": [ "https://example.com/bar"],
                            "name": [ "bar" ]
                        },
                        "value": "bar"
                    },
                    {
                        "type": [ "h-entry"],
                        "properties": {
                            "url": ["https://example.com/foo" ],
                            "name": ["foo"]
                        },
                        "value": "foo"
                    }
                ]
            ]
        }
    ],
…
```
Note how `properties` of the `h-feed`  has been turned into *two nested lists* somehow, which is completely invalid output.

Potentially related, when nesting the two h-entries, somehow a property named `0` gets generated, which is also badly wrong (note that no `0` appears in the input)

```html
<div class=" h-feed pt-2">
  <div class="p-4 h-entry">
    <a class="u-url" href="https://example.com/bar">bar </a>
    <div class="p-4 h-entry">
      <a class="u-url" href="https://example.com/foo">foo</a>
    </div>
  <div>
</div>
```

parsed as
```json
{
    "items": [
        {
            "type": [ "h-feed"],
            "properties": [
                [
                    {
                        "type": ["h-entry"],
                        "properties": {
                            "url": ["https://example.com/bar"],
                            "0": [
                                {
                                    "type": ["h-entry"],
                                    "properties": {
                                        "url": ["https://example.com/foo" ],
                                        "name": [ "foo" ]
                                    },
                                    "value": "foo"
                                }
                            ]
                        },
                        "value": "bar foo"
                    }
                ]
            ]
        }
    ],
```

Maybe related to #246
