Rule with pseudo selector has false params property
We've been struggling with some baddish logic in postcss-less while analyzing rules. Given this rule:

``` css
.test1,
.test2:not(.test3) {
    width: 100%;
}
```

The resulting node looks like this:

``` js
Rule {
  raws:
   { before: '',
     between: ' ',
     params: { value: '(.test3)', raw: '(.test3) ' },
     semicolon: true,
     after: '\n' },
  type: 'rule',
  nodes:
   [ Declaration {
       raws: [Object],
       type: 'decl',
       parent: [Circular],
       source: [Object],
       prop: 'width',
       value: '100%' } ],
  parent:
   Root { ... },
  source:
   { start: { line: 1, column: 1 },
     input:
      Input {
        css: '.test1,\n.test2:not(.test3) {\n    width: 100%;\n}\n',
        id: '<input css 1>' },
     end: { line: 4, column: 1 } },
  selector: '.test1,\n.test2:not(.test3)',
  params: '(.test3)',
  lastEach: 4,
  indexes: {},
  selectorAst:
   Root { ... }
```

You'll notice that this is not a mixin definition or use, but the `params` property is being assigned based on the pseudo selector `:not` value. On the surface, this looks like a bug. The value of the pseudo selector should be simply part of the selector, as it's not treated any different in plain css, and params should be empty.

### Additional contract requirements

- In particular, parsing `.test2:not(.test3) {}` must leave the resulting rule's `params` property `undefined`.
