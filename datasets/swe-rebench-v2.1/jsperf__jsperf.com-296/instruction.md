“Unexpected response from browserscope.org” shouldn’t prevent new test creation
Whenever the “Unexpected response from browserscope.org” occurs, jsPerf should still create the test, just without a Browserscope ID.

When the test page is accessed we can re-attempt to get a Browserscope ID for this test.
