Helper _init() hook is called twice after upgrade to 1.1.7
#### What are you trying to achieve?
Initialize a helper.
#### What do you get instead?
Helper _init() hook is called twice, once before bootstrap and again after. Before upgrading it was only called once, before bootstrap. This change broke our suite initialization that relied on this particular sequence.
### Details

* CodeceptJS version: 1.1.7
* NodeJS Version: 8.2.1
* Operating System: MacOS 10.12.6
* WebDriverIO
* Configuration file:

```js
exports.config = {
  bootstrap,
  name: '...',
  mocha: {},
  tests: './{,+(bin|core|features|app_modules)/**/tests/acceptance/}*.acctests.js',
  output: './acceptanceScreenshots',
  timeout: 20000,
  // custom settings.
  customSettings: {
  ...
  },
  helpers: {
    WebDriverIO: {
      url: appUrl,
      browser: 'chrome',
      windowSize: '1024x1000',
      restart: false,
      keepCookies: false,
      manualStart: true
    },
    FileSystem: {},
    REST: {
      endpoint: apiUrl,
      resetHeaders: true,
    },
    ApiDataFactory: {
      endpoint: apiUrl,
      cleanup: true,
      factories: {
      ...
      },
      REST: {
        resetHeaders: true
      }
    },
    AppHelper: {
      require: './app_modules/acceptanceTest/appHelper.js'
    },
   ...
  },
  include: {
    // Misc app components/pages
   ...
  }
```
Thank you.
