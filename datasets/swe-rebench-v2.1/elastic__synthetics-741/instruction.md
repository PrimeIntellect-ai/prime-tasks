Passing headless `false` still executes tests in headless mode
+ If you pass `headless: false` to `PlaywrightOptions`, the test is expected to run in regular (non-headless) mode, but its not working correctly as CLI args `headless` takes precedence.
