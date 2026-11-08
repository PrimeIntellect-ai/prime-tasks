`{{ arr | safe }}` should not escape
`render('{{ arr | safe }}', { arr: [ '<html>' ] })` => `&lt;html&gt;`

https://github.com/mozilla/nunjucks/blob/master/src/runtime.js#L190

@vecmezoni is this a bug or user should use `{{ arr | join | safe }}` ?
