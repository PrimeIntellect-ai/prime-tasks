SyntaxError for nested block params
```hbs
    {{#x-select value=letter action=(action (mut letter)) as |xs|}}
        <option>Filter by the letter...</option>
        {{#each alphabet as |letter|}}
            {{#xs.option value=letter}}{{ letter }}{{/xs.option}}
        {{/each}}
    {{/x-select}}
```

leads to

```
undefined: `xs.option` is not a valid name for a helper on line 23. (cargo/templates/crates):
`Error: `xs.option` is not a valid name for a helper on line 23.
    at SyntaxError.Error (native)
    at new SyntaxError (/Users/tbieniek/Code/crates.io/node_modules/@glimmer/syntax/dist/commonjs/es5/lib/errors/syntax-error.js:14:27)
    at assertIsSimplePath (/Users/tbieniek/Code/crates.io/node_modules/ember-template-lint/node_modules/@glimmer/compiler/dist/commonjs/es5/lib/template-compiler.js:476:15)
    at TemplateCompiler.prepareHelper (/Users/tbieniek/Code/crates.io/node_modules/ember-template-lint/node_modules/@glimmer/compiler/dist/commonjs/es5/lib/template-compiler.js:342:9)
    at TemplateCompiler.block (/Users/tbieniek/Code/crates.io/node_modules/ember-template-lint/node_modules/@glimmer/compiler/dist/commonjs/es5/lib/template-compiler.js:196:14)
    at /Users/tbieniek/Code/crates.io/node_modules/ember-template-lint/node_modules/@glimmer/compiler/dist/commonjs/es5/lib/template-compiler.js:71:25
    at Array.forEach (native)
    at TemplateCompiler.process (/Users/tbieniek/Code/crates.io/node_modules/ember-template-lint/node_modules/@glimmer/compiler/dist/commonjs/es5/lib/template-compiler.js:64:17)
    at Function.compile (/Users/tbieniek/Code/crates.io/node_modules/ember-template-lint/node_modules/@glimmer/compiler/dist/commonjs/es5/lib/template-compiler.js:57:32)
    at precompile (/Users/tbieniek/Code/crates.io/node_modules/ember-template-lint/node_modules/@glimmer/compiler/dist/commonjs/es5/lib/compiler.js:45:60)
    at Linter.verify (/Users/tbieniek/Code/crates.io/node_modules/ember-template-lint/lib/index.js:110:7)
    at TemplateLinter.processString (/Users/tbieniek/Code/crates.io/node_modules/ember-cli-template-lint/broccoli-template-linter.js:101:28)
    at Promise.then.result.output (/Users/tbieniek/Code/crates.io/node_modules/broccoli-persistent-filter/lib/strategies/persistent.js:41:23)
    at initializePromise (/Users/tbieniek/Code/crates.io/node_modules/rsvp/dist/rsvp.js:589:5)
    at new Promise$1 (/Users/tbieniek/Code/crates.io/node_modules/rsvp/dist/rsvp.js:1077:33)
    at /Users/tbieniek/Code/crates.io/node_modules/broccoli-persistent-filter/lib/strategies/persistent.js:40:18`@ 1 ms
```

am I doing something wrong?

```
$ yarn list ember-cli-template-lint
yarn list v0.25.1
└─ ember-cli-template-lint@0.7.0
```
