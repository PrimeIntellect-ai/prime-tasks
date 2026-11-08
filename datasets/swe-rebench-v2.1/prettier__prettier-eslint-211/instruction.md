Fix failing tests
Tests are currently failing and it's keeping us from releasing any new code for this package.

The tests are failing because `prettier` updated `comsiconfig` and it's reading files a bit differently and is resulting in failing tests because of how we mock the filesystem for our tests.

We need to find a better way to mock the filesytem i.e. the `fs` module and the `require` calls.

@azz @vjeux Feel free to chime in if you have experience with testing and mocking or mentioning people with testing skillz
