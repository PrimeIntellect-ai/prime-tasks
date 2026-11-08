Newest htmlbars release (0.14.17) breaks block indentation rule
[This change](https://github.com/tildeio/htmlbars/commit/29a77fb596059d207e95df9f7d2fc40e6c77f120#diff-77a79c73c5f2afcef7e58ed15c331b3bR35) breaks the block indentation rule because now [this check](https://github.com/rwjblue/ember-cli-template-lint/blob/master/ext/plugins/lint-block-indentation.js#L174) passes for text nodes. This is because this:

```handlebars
{{#if foo}}
  {{foo}}
{{/if}}
```

[HIDDEN] [HIDDEN] the block indentation logic flags as incorrect, and then when trying to log the error, throws an exception on [this line](https://github.com/rwjblue/ember-cli-template-lint/blob/master/ext/plugins/lint-block-indentation.js#L216) [HIDDEN]

[HIDDEN], but I don't have time to prepare a fix right now. If somebody else does, great, otherwise maybe we can just pin the version of htmlbars to 0.14.16 until we have time to get in a fix?

### Additional contract requirements

- Leading whitespace inside a correctly indented block must not by itself produce an indentation diagnostic or cause linting to throw an exception.
- The block-indentation rule must still report genuine indentation problems while processing block contents that include text.
