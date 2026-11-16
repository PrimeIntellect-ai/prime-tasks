FR: Heading Blank Lines Rule should not insert empty lines between headings
## Is Your Feature Request Related to a Problem? Please Describe.

Right now, the rule [Heading Blank Lines](https://github.com/platers/obsidian-linter/blob/master/docs/rules.md#heading-blank-lines) creates blank lines above/below headings, except when it's a heading at the start or at the end of the document.

However, if you have two consecutive headings, e.g. a h2 without paragraph, only followed by h3s with paragraphs, it results in the linter inserting a line break between the two headings. In my view, it looks a bit weird, especially if you have the "bottom" sub-option disabled. In that case, it will literally insert a blank below a heading, even though the respective option has been disabled.

## Describe the Solution You'd Like

At least when the bottom sub-option has been disabled, the rule should not insert a blank below a heading.

**Please include an example where applicable:**

right now, it gets turned into this
``` markdown
...paragraph...

# foobar 1

## foobar 2
...paragraph...
```

but it should better look like this
``` markdown
...paragraph...

# foobar 1
## foobar 2
...paragraph...
```

## Describe Alternatives You've Considered
well, creating a custom rule, I guess?

### Additional contract requirements

- When `bottom` is disabled and two headings have no content between them, any existing blank lines between them must remain unchanged.
