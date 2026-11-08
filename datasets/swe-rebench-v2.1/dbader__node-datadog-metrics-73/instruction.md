Export NullReporter for external use
I think it would be super helpful to publicly export the [`NullReporter` class](https://github.com/dbader/node-datadog-metrics/blob/023acfa3a2c5d8dd3f5bbb48c8c02467b2519559/lib/reporters.js#L7-L20) (or just the whole `reporters` module) so consumers can use it. In particular, it’s nice for:
- Tests (plenty of test frameworks have automatic mocking, but setting up an actual `BufferedMetricsLogger` instance with no auto flush and no reporter lets you better inspect exactly what the framework would have sent).
- Disabling metrics in development or temporarily in production (having a version of the logger that doesn’t send is nicer than not creating a logger, because then you don’t have to guard every call-site or make your own mock).

I’d be happy to make a quick PR for this if that’s helpful. (If so, could you let me know what the minimum supported version of Node.js should be (I don’t see it listed anywhere), and therefore whether `exports` in `package.json` or just exporting it from the `index.js` file is preferable?)
