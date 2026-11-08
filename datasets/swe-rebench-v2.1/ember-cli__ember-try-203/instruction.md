`ember try:ember` dies after first failed scenario with 1.0.0-beta.3
When using ember-try 1.0.0-beta.3, `ember try:ember` exits immediately after a single scenario fails, without running the remaining scenarios or outputting the summary. (0.2.23 and 1.0.0-beta.1 work as expected.)

I created a new addon as a testcase, with a single failing test in it: https://github.com/pgengler/ember-try-testcase

To reproduce:
1) Clone the test addon and run `yarn install`.
2) Run `ember try:ember`. Only the "default" scenario runs, and execution stops with an error message displayed ([see output](https://gist.github.com/pgengler/e8d617a6cf43764b31593f8eac6b247d))

To see beta-1 behavior:
1) Check out the `beta-1` branch of the test addon and run `yarn install`.
2) Run `ember try:ember`. The scenarios all run to completion. ([see output](https://gist.github.com/pgengler/04c0c2cda6a00320dfde63549220c9f4))

### Additional contract requirements

- If a scenario's command fails, `ember try:ember` must continue running the remaining scenarios.
- After a scenario fails, `ember try:ember` must still output the run summary.
