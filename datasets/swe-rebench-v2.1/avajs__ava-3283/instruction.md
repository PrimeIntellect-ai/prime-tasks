config to control handling for tests that 'Failed to exit' - v6+ issue
With Node 18.18, I am unable to get Ava to not fail the test suite when a module does not exit. I run integration tests with a local database and want to keep the database pool open.

In 5.3.1, this worked fine but it breaks after upgrading and no other changes on my end.

Please enable some kind of way to set up the configuration to forcibly exit and pass if all tests ran & passed, or just let me know what I'm missing here. I've already tried toggling worker threads and I didnt see anything else usable in the docs for the configuration.

### Additional contract requirements

- Add a public function `registerCompletionHandler(handler: () => void) -> void` exported from the main AVA entrypoint (the `ava` module).
- The handler is invoked after AVA has completed a test run without uncaught exceptions or unhandled rejections.
- Handlers are invoked in order of registration.
- The handler's return value is ignored; results are not awaited.
- The function is also available to TypeScript consumers importing from the main AVA entrypoint.
