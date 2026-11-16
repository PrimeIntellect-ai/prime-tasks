Allow hooking into onopentag and onclosetag
## The problem to solve

I'm trying to solve the issue described here https://github.com/apostrophecms/sanitize-html/issues/49. I think I'm quite close to doing it correctly, but current `sanitize-html` functions and configuration seem too limiting to express this.

Imagine performing the following two modifications to HTML:
1. insert a space before the first text block after a disallowed element has just opened
2. insert a space before the first text block after a disallowed element has just closed

For example (assume we disallow all `<div>`):
```html
<div>hello</div>there -> "hello there"
hello<div>there</div> -> "hello there"
<div>hello</div><div>there</div> -> " hello there"
<div><div>hello</div>there</div> -> " hello there"
```

Especially note scenarios like this (where we can't simply add a space before each closing `</div>`):
```html
<div><text>this is a text block</text><text>this is a text block</text></div>
```

I don't think this is currently possible (but correct me if I'm wrong).

## Proposed solution

Allow hooking into `ontagopen` and `ontagclose` events and just pass `tag` names into the listeners like this:
```js
sanitizeHtml(
  '<p>This is <a href="http://www.linux.org"></a><br/>Linux</p>',
  {
    onOpenTag: function(tag) {
      console.log(`${tag} opened`);
    },
    onCloseTag: function(tag) {
      console.log(`${tag} closed`);
    },
  }
);
```

## Alternatives

Tried all sorts of hacky ways of using `transformTags` and `exclusiveFilter` and `textFilter` but in combination with `discard` it doesn't work.

Maybe an alternative could be if `exclusiveFilter` could allow applying the `discard` mode, then it *may* be possible to hook into the `onclosetag` indirectly. But that's hacky.
