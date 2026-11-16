Allow hooking into responses
Related: https://github.com/unjs/nitro/issues/1396

Currently, it is not possible to hook into responses (that are handled by h3 not directly with `res.end`). In order to do this, we might refactor `app.ts` and allow hooking into directly returned responses and allow to hook into using custom callback `onBeforeResponse(event, { body })`.

This can be later used by higher order frameworks to support custom response rewrite handling and logging.

At this point, i also like to gether some common usecase ideas before moving forward (mainly because it also adds some overhead even if callback is not used)

### Additional contract requirements

`createApp(options)` accepts the following optional lifecycle hooks in its options object. Each hook may return a Promise, and the request is not considered finished until the returned promise resolves.

- `onRequest?: (event: H3Event) => void | Promise<void>` — invoked once per request, before any route handling.
- `onBeforeResponse?: (event: H3Event, response: { body?: unknown }) => void | Promise<void>` — invoked after a handler returns a value but before the response is written. `response.body` is the value returned by the handler.
- `onAfterResponse?: (event: H3Event, response?: { body?: unknown }) => void | Promise<void>` — invoked after a handler returns a value or writes a response manually. When a handler returns a value, `response.body` is that value. The hook is also invoked when the response is written manually (for example with `send`).
