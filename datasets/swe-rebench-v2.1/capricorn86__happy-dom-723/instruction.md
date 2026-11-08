timeStamp property missing from Event & CustomEvent
**Is your feature request related to a problem? Please describe.**

[`Event`](https://github.com/capricorn86/happy-dom/blob/master/packages/happy-dom/src/event/Event.ts#L11-L20) (and hence [`CustomEvent`](https://github.com/capricorn86/happy-dom/blob/master/packages/happy-dom/src/event/events/CustomEvent.ts)) are missing the `timeStamp` property. This means that for example unit tests running with `happy-dom` will fail if they try to access the undefined `timeStamp` property.

Example code:
```ts
console.debug("TYPEOF timeStamp", typeof event.timeStamp);
```
```sh
TYPEOF timeStamp undefined
```

**Describe the solution you'd like**
Happy DOM should assign the `timeStamp` property.

~~(I will be providing a pull request.)~~ I've provided a **Pull Request for this at https://github.com/capricorn86/happy-dom/pull/723**


**Describe alternatives you've considered**
- Hack my own tests to check if `timeStamp` is undefined – _basically making the tests useless_
- Override the global `CustomEvent` – _feels dirty_


**Additional context**

Looking at [`jsdom` implementation of `timeStamp`](https://github.com/jsdom/jsdom/blob/82c4d54aa7062e6e7402a27502639e01836d694d/lib/jsdom/living/events/Event-impl.js#L39) is just a `Date.now()` – which does not match the specification (see [MDN](https://developer.mozilla.org/en-US/docs/Web/API/Event/timeStamp) and [Spec](https://dom.spec.whatwg.org/#ref-for-dom-event-timestamp%E2%91%A0)):
> _This value is the number of milliseconds elapsed from the beginning of the time origin until the event was created. If the global object is [Window](https://developer.mozilla.org/en-US/docs/Web/API/Window), the time origin is the moment the user clicked on the link, or the script that initiated the loading of the document. In a worker, the time origin is the moment of creation of the worker._

I think we could do better: My proposed solution is to use `performance.timeOrigin` as the time origin to resolve the relative Event `timeStamp` value.

### Additional contract requirements

- `Event` exposes a public `timeStamp` property. Its value is a number equal to the value returned by `performance.now()` at the moment the event object is created.
- A `CustomEvent` instance also exposes a `timeStamp` property with the same behaviour.
