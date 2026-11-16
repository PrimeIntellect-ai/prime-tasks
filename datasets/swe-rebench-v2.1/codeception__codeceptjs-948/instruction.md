AfterSuite can't be defined after first Scenario
#### What are you trying to achieve?

I expect `AfterSuite` to run if it is placed at the end of a test file.

#### What do you get instead?

It does not run. It only runs when you define `AfterSuite` before the first `Scenario`.

For some reason, [context.AfterSuite](https://github.com/Codeception/CodeceptJS/blob/master/lib/interfaces/bdd.js#L121-L123) [HIDDEN]

This means any AfterSuite defined after the first Scenario will not be registered. This is unexpected and undocumented behavior.

I haven't submitted a fix because there might be a good reason that `AfterSuite` does not register the hook directly.
