Fix parsing class properties with newlines
Tracked this one down via https://github.com/indieweb/indiewebify-me/issues/102. Initially I thought that issue was due to the php-mf2 version (it did need to be updated), but I realized once I parsed with php-mf2 0.5.0, the `p-name` was not being found when there's new lines between the classes.

I tried a several variations based on that source HTML and came up with some minimal tests:

```html
<div class="h-entry">
<h1 class="post_title__text
p-name">Page Title</h1>
<p class="p-summary">A summary so the p-name won't be implied. This test demonstrates p-name is not being parsed.</p>
</div>
```

Parsed result [with 0.5.0](http://php.microformats.io/?id=20221008222422564):

```json
{
    "items": [
        {
            "type": [
                "h-entry"
            ],
            "properties": {
                "summary": [
                    "A summary so the p-name won't be implied. This test demonstrates p-name is not being parsed."
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

And with implied p-name parsing:

```html
<div class="h-entry">
<h1 class="post_title__text
p-name">Page Title</h1>
<p> Here is some content without microformats. If the parser does not find p-name above, it will try to imply p-name, which will include this text as well. </p>
<p> implied p-name parsing will occur if the parser doesn't find any p-* or e-* properties. </p>
</div>
```

Parsed result with [php-mf2 0.5.0](http://php.microformats.io/?id=20221008221625954)

```json
{
    "items": [
        {
            "type": [
                "h-entry"
            ],
            "properties": {
                "name": [
                    "Page Title\nHere is some content without microformats. If the parser does not find p-name above, it will try to imply p-name, which will include this text as well.\nimplied p-name parsing will occur if the parser doesn't find any p-* or e-* properties."
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
