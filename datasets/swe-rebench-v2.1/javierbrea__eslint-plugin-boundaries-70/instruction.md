Fatal error on dependency scanning - dependencyInfo.name might be null
Hey,

thanks for this great library 👍  I was looking for a JS/TS library to do Architecture Tests (like https://www.archunit.org/, but inJS), and IMHO your library is extremely close to that!

I ran it with a medium-sized codebase; and possibly found an error:

In my case, the system broke with the following error:

```
TypeError: Cannot read property 'split' of undefined
Occurred while linting /Users/sebastian/src/kiwigrid/solarwatt-smart-setup/src/Redux/Sagas/BatteryRebootProcess.ts:2
    at ImportDeclaration (/Users/sebastian/src/kiwigrid/solarwatt-smart-setup/node_modules/eslint-plugin-boundaries/src/rules/no-external.js:62:57)
    at /Users/sebastian/src/kiwigrid/solarwatt-smart-setup/node_modules/eslint/lib/linter/safe-emitter.js:45:58
    at Array.forEach (<anonymous>)
    at Object.emit (/Users/sebastian/src/kiwigrid/solarwatt-smart-setup/node_modules/eslint/lib/linter/safe-emitter.js:45:38)
    at NodeEventGenerator.applySelector (/Users/sebastian/src/kiwigrid/solarwatt-smart-setup/node_modules/eslint/lib/linter/node-event-generator.js:254:26)
    at NodeEventGenerator.applySelectors (/Users/sebastian/src/kiwigrid/solarwatt-smart-setup/node_modules/eslint/lib/linter/node-event-generator.js:283:22)
    at NodeEventGenerator.enterNode (/Users/sebastian/src/kiwigrid/solarwatt-smart-setup/node_modules/eslint/lib/linter/node-event-generator.js:297:14)
    at CodePathAnalyzer.enterNode (/Users/sebastian/src/kiwigrid/solarwatt-smart-setup/node_modules/eslint/lib/linter/code-path-analysis/code-path-analyzer.js:634:23)
    at /Users/sebastian/src/kiwigrid/solarwatt-smart-setup/node_modules/eslint/lib/linter/linter.js:936:32
    at Array.forEach (<anonymous>)
```

... while parsing the line:

```
import { RootState } from '../index';
```

See the related Pull Request for a possible fix :-)

All the best, and keep up the good work,
Sebastian
