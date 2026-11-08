Error while parsing dynamic route map in no-shadow-route-definition rule
Hey everyone! I've faced an issue while upgrading an app to Ember 3.23, which looks like a bug in `eslint-plugin-ember` parser.

There's a route map that looks similar to this:

```js
const SPORTS = ['footbal', 'baseball', 'basketball'];

Router.map(function() {
  this.route('sports', function () {
    for (let sport of SPORTS) {
      this.route(sport, function () {
      	this.route('info');

        if (sport === 'football') {
          this.route('super-bowl');
        }
      });
    }
  })
});
```
The real case is more complex, but this example gives an understanding of the structure.

While processing this route map ESLint breaks and throws the following error:
```
TypeError: Cannot read property 'startsWith' of undefined
Occurred while linting /Users/artur/path/to/app/sports/app/router.js:14
    at getRouteBasePath (/Users/artur/path/to/app/sports/node_modules/eslint-plugin-ember/lib/rules/no-shadow-route-definition.js:128:18)
    at getRouteInfo (/Users/artur/path/to/app/sports/node_modules/eslint-plugin-ember/lib/rules/no-shadow-route-definition.js:93:20)
    at CallExpression (/Users/artur/path/to/app/sports/node_modules/eslint-plugin-ember/lib/rules/no-shadow-route-definition.js:60:27)
    at /Users/artur/.config/yarn/global/node_modules/eslint/lib/linter/safe-emitter.js:45:58
    at Array.forEach (<anonymous>)
    at Object.emit (/Users/artur/.config/yarn/global/node_modules/eslint/lib/linter/safe-emitter.js:45:38)
    at NodeEventGenerator.applySelector (/Users/artur/.config/yarn/global/node_modules/eslint/lib/linter/node-event-generator.js:256:26)
    at NodeEventGenerator.applySelectors (/Users/artur/.config/yarn/global/node_modules/eslint/lib/linter/node-event-generator.js:285:22)
    at NodeEventGenerator.enterNode (/Users/artur/.config/yarn/global/node_modules/eslint/lib/linter/node-event-generator.js:299:14)
    at CodePathAnalyzer.enterNode (/Users/artur/.config/yarn/global/node_modules/eslint/lib/linter/code-path-analysis/code-path-analyzer.js:711:23)
```

The error message points to this line:
```js
this.route(sport, function () {
```
and breaks [here](https://github.com/ember-cli/eslint-plugin-ember/blob/master/lib/rules/no-shadow-route-definition.js#L128) because `routePath` is `undefined` (presumably because it's a variable, which isn't defined during static analysis).

It doesn't help to just disable the rule neither in config nor inline – seems like ESLint parses the files eagerly and only takes excludes into account for reporting.

Is it a known issue? I didn't find anything related searching through the issues in this repository.
