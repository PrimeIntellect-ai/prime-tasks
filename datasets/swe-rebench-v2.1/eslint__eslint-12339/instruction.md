[6.5.0] `no-useless-rename` with `babel-eslint` crash at rest properties
**Tell us about your environment**

* **ESLint Version:** 6.5.0
* **Node Version:** 12.10.0
* **npm Version:** 6.10.3

**What parser (default, Babel-ESLint, etc.) are you using?**
babel eslint

**Please show your full configuration:**

<details>
<summary>Configuration</summary>

<!-- Paste your configuration below: -->
```js
{
  "extends": [
    "airbnb",
    "plugin:react/all"
  ],
  "env": {
    "browser": true,
    "node": true,
    "es6": true
  },
  "parser": "babel-eslint",
  "plugins": [
    "react",
    "simple-import-sort"
  ],
  "rules": {
    "arrow-parens": [
      "error",
      "always"
    ],
    "camelcase": "error",
    "comma-dangle": [
      "error",
      "never"
    ],
    "curly": [
      "error",
      "all"
    ],
    "func-names": "error",
    "indent": [
      "error",
      2
    ],
    "max-len": [
      "error",
      {
        "code": 120,
        "ignoreUrls": true,
        "tabWidth": 2
      }
    ],
    "no-param-reassign": "off",
    "no-underscore-dangle": "off",
    "no-plusplus": "off",
    "no-console": "error",
    "no-unused-vars": [
      "error",
      {
        "argsIgnorePattern": "dispatch"
      }
    ],
    "simple-import-sort/sort": "error",
    "sort-keys": [
      "error",
      "asc",
      {
        "natural": true,
        "caseSensitive": false
      }
    ],
    "sort-vars": "error",
    "react/jsx-indent": [
      "error",
      2
    ],
    "react/jsx-indent-props": [
      "error",
      2
    ],
    "react/jsx-max-depth": "off",
    "react/jsx-no-literals": "off",
    "react/jsx-one-expression-per-line": "off",
    "react/destructuring-assignment": "off",
    "react/jsx-key": "off",
    "react/no-did-mount-set-state": "off",
    "react/no-set-state": "off",
    "react/prefer-stateless-function": "off",
    "react/jsx-props-no-spreading": "off",
    "jsx-a11y/click-events-have-key-events": "off",
    "jsx-a11y/no-static-element-interactions": "off",
    // TODO: All rules below here will eventually be accounted for
    "react/jsx-handler-names": "off",
    "react/prop-types": "off",
    "react/jsx-fragments": "off"
  }
}
```

</details>

**What did you do? Please include the actual source code causing the issue, as well as the command that you used to run ESLint.**

<!-- Paste the source code below: -->
```js
import { Button as MuiButton, withStyles } from '@material-ui/core';
import { darken } from '@material-ui/core/styles';
import * as React from 'react';
import { Link } from 'react-router-dom';

class Button extends React.Component {
  // TODO: Implement
  shouldComponentUpdate() {
    return true;
  }

  render() {
    const {
      classes, href, icon, ...otherProps
    } = this.props;

    const buttonContent = (
      <div className={classes.buttonChildrenContainer}>
        {icon && (
          <div className={classes.buttonIcon}>
            <img
              alt="button-icon"
              className={classes.buttonIconImg}
              src={icon}
            />
          </div>
        )}
        <div className={classes.buttonText}>{this.props.children}</div>
      </div>
    );

    return href ? (
      <Link to={`/${href}`}>
        <MuiButton
          className={classes.root}
          color="primary"
          fullWidth
          variant="contained"
          {...otherProps}
        >
          {buttonContent}
        </MuiButton>
      </Link>
    ) : (
      <MuiButton
        className={classes.root}
        color="primary"
        fullWidth
        variant="contained"
        {...this.props}
      >
        {buttonContent}
      </MuiButton>
    );
  }
}

const styles = (theme) => ({
  buttonChildrenContainer: {
    display: 'flex',
    height: 48,
    width: '100%'
  },
  buttonIcon: {
    backgroundColor: 'white',
    borderRadius: '3px 0 0 3px',
    padding: '10px 4px',
    width: 48
  },
  buttonIconImg: {
    maxHeight: '100%',
    maxWidth: '100%'
  },
  buttonText: {
    flex: 1,
    fontSize: 16,
    paddingTop: 10,
    textAlign: 'center'
  },
  root: {
    '&:hover': {
      backgroundColor: darken(theme.palette.secondary.main, 0.1)
    },
    backgroundColor: theme.palette.secondary.main,
    boxShadow: 'none',
    padding: 2,
    textTransform: 'none'
  }
});

export default withStyles(styles, { withTheme: true })(Button);
```

<!-- Paste the command you used to run ESLint: -->
```bash
./node_modules/.bin/eslint --ext .js --ext .jsx .
```

**What did you expect to happen?**
Everything to lint fine as it does in `6.4.0`

**What actually happened? Please include the actual, raw output from ESLint.**
```
▶ npm run lint --prefix packages/client

> client@1.0.0 lint /Users/jakeleventhal/Projects/ecominate/packages/client
> ../../node_modules/.bin/eslint --ext .js --ext .jsx .

TypeError: Cannot read property 'type' of undefined
Occurred while linting /Users/jakeleventhal/Projects/ecominate/packages/client/src/view/SignInUp/Components/Button.jsx:13
    at checkDestructured (/Users/jakeleventhal/Projects/ecominate/node_modules/eslint/lib/rules/no-useless-rename.js:104:43)
    at /Users/jakeleventhal/Projects/ecominate/node_modules/eslint/lib/linter/safe-emitter.js:45:58
    at Array.forEach (<anonymous>)
    at Object.emit (/Users/jakeleventhal/Projects/ecominate/node_modules/eslint/lib/linter/safe-emitter.js:45:38)
    at NodeEventGenerator.applySelector (/Users/jakeleventhal/Projects/ecominate/node_modules/eslint/lib/linter/node-event-generator.js:253:26)
    at NodeEventGenerator.applySelectors (/Users/jakeleventhal/Projects/ecominate/node_modules/eslint/lib/linter/node-event-generator.js:282:22)
    at NodeEventGenerator.enterNode (/Users/jakeleventhal/Projects/ecominate/node_modules/eslint/lib/linter/node-event-generator.js:296:14)
    at CodePathAnalyzer.enterNode (/Users/jakeleventhal/Projects/ecominate/node_modules/eslint/lib/linter/code-path-analysis/code-path-analyzer.js:646:23)
    at /Users/jakeleventhal/Projects/ecominate/node_modules/eslint/lib/linter/linter.js:935:32
    at Array.forEach (<anonymous>)
npm ERR! code ELIFECYCLE
npm ERR! errno 2
npm ERR! client@1.0.0 lint: `../../node_modules/.bin/eslint --ext .js --ext .jsx .`
npm ERR! Exit status 2
npm ERR!
npm ERR! Failed at the client@1.0.0 lint script.
npm ERR! This is probably not a problem with npm. There is likely additional logging output above.

npm ERR! A complete log of this run can be found in:
npm ERR!     /Users/jakeleventhal/.npm/_logs/2019-09-29T06_40_12_714Z-debug.log
```

**Are you willing to submit a pull request to fix this bug?**
No
