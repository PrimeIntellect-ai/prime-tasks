Global monitor options enabled and retestOnFailure are ignored
Not all global `synthetics.config.ts` settings for [MonitorConfig](https://github.com/elastic/synthetics/blob/main/src/dsl/monitor.ts#L56-L79) get applied to individual monitors.

Example valid `synthetics.config.ts` for cases where by default all monitors (`enabled`), all alerts (`alert`) and retest on failure (`retestOnFailure`) should be disabled:
```ts
import type { SyntheticsConfig } from "@elastic/synthetics";

export default (env: string) => {
  const config: SyntheticsConfig = {
    params: {},
    playwrightOptions: {},
    /**
     * Configure global monitor settings
     */
    monitor: {
      schedule: 10,
      locations: [],
      privateLocations: [],
      alert: {
        status: {
          enabled: false,
        },
        tls: {
          enabled: false,
        },
      },
      enabled: false,
      throttling: false,
      retestOnFailure: false,
    },
    /**
     * Project monitors settings
     */
    project: {
      id: "foo",
      url: "https://example.com/",
      space: "default",
    },
  };
  if (env !== "development") {
    /**
     * Override configuration specific to environment
     * Ex: config.params.url = ""
     */
  }
  return config;
};

```

Expected monitor config would be something like this:
```ts
const j1 = new Journey({ name: 'j1', tags: ['foo*'] }, () => {});
j1.updateMonitor({
  id: 'test-j1',
  schedule: 3,
  locations: ['united_kingdom'],
  privateLocations: ['spain'],
});
runner.addJourney(j1);

const monitors = runner.buildMonitors( /* put global settings here */ );
expect(monitors.length).toBe(1);
console.dir(monitors[0].config);
expect(monitors[0].config).toEqual({
  // from local config
  id: 'test-j1',
  name: 'j1',
  type: 'browser',
  tags: ['foo*'],
  locations: ['united_kingdom'],
  privateLocations: ['spain'],
  schedule: 3,
  // Params and PlaywrightOptions, not in scope of this issue
  playwrightOptions: {},
  params: {},
  // from global config
  enabled: false,
  retestOnFailure: false,
  throttling: false,
  alert: { status: { enabled: false }, tls: { enabled: false } },
  screenshot: undefined,
});
```
But instead you're getting `MonitorConfig`:
```ts
{
  throttling: false,
  schedule: 3,
  locations: [ 'united_kingdom' ],
  privateLocations: [ 'spain' ],
  params: {},
  playwrightOptions: {},
  screenshot: undefined,
  tags: [ 'foo*' ],
  alert: { status: { enabled: false }, tls: { enabled: false } },
  name: 'j1',
  id: 'test-j1',
  type: 'browser'
}
```
with `enabled` and `retestOnFailure` settings completely ignored.
Tests for this also seem to be wrong, because [runner.updateMonitor](https://github.com/elastic/synthetics/blob/main/__tests__/core/runner.test.ts#L757) gets executed by test with global settings and `runner.buildMonitors(options)` is called with local settings which is wrong, `runner.buildMonitors(options)` should be called with global settings and `runner.updateMonitor` should not be executed at all, because it's invoked by `runner.buildMonitors` [here](https://github.com/elastic/synthetics/blob/main/src/core/runner.ts#L410).

### Additional contract requirements

- `Runner.buildMonitors` accepts an options object that includes `enabled?: boolean` and `retestOnFailure?: boolean`. These values are the defaults applied to every monitor it builds.
- `Journey.updateMonitor` accepts an options object that includes `enabled?: boolean` and `retestOnFailure?: boolean`. A value set for a journey overrides the corresponding default supplied to `Runner.buildMonitors`.
