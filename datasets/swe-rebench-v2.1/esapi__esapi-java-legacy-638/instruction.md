Incorrrect result for `isEnabled()` in `Slf4JLogger`
`isEnabled(int esapiLevel)` in `Slf4JLogger` returns incorrect result. [HIDDEN]

## Steps to reproduce (in 2.2.3.1)
* Create a logger for `SomeClass` in log4j.xml. Set its level to `info` level. Like so:
```
<Logger name="com.SomeClass" level="info">
    <appender-ref ref="SOME-APPENDER-REF"/>
</Logger>
```
* `SomeClass` looks like:
```
private static final Logger LOG = ESAPI.getLogger(SomeClass.class);;
...
if(LOG.isDebugEnabled()) {
    // do some heavy operation here.
}
```

## Expected result
* With above logger config `LOG.isDebugEnabled()` will return `false`.

## Actual result
* `LOG.isDebugEnabled()` returns `true`.

## Some more observations
* Even though the enabled checks (like `isDebugEnabled()`, `isInfoEnabled()`, etc.) fail, the actual log statements (like `debug()`, `info()`) do honor the log levels.
* This has a big perf impact because of all the crap that might go in `LOG.isDebugEnabled()` check.

### Additional contract requirements

- For `Slf4JLogger`, when the configured level is INFO, `isDebugEnabled()` must return `false`.
