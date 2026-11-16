ParseError should contain err.statusCode
`curl -v https://api.github.com/repos/震动/generator-test` should output a json but it does print an HTML pages, which gives a `ParseError` if we use `got()` with `options.json=true`. Though, I was expecting that the ParseError contained the `err.statusCode` property, which doesn't at the moment. It has to be accessed via `err.response.statusCode` which kind sucks :(

Thoughts?
