`.emit()` should not receive the returned value from `.on()`
I noticed that you can return a value from an event handler, e.g.,

```javascript
event.on("myEvent", () => 123);
const value = await event.emit("myEvent");
value[0] === 123; // true
```

But the `Emittery.Typed` types don't support the return type, so typescript thinks `value` is always `void`.

Is this a feature that you'd like to be supported in the TypeScript types? If so, I can probably find some time to put a PR together. Are there any gotchas I should be aware of?

I hacked together something to make it "work" for my code base (it's not quite right), though this would result in breaking changes:

```typescript
class Typed<EventDataMap extends Events, EmptyEvents extends EventName = never> extends Emittery.Typed {
	on<Name extends EventNameFromDataMap<EventDataMap>>(eventName: Name, listener: (eventData: Parameters<EventDataMap[Name]>[0]) => void): Emittery.UnsubscribeFn;
	on<Name extends EmptyEvents>(eventName: Name, listener: () => void): Emittery.UnsubscribeFn;

	events<Name extends EventNameFromDataMap<EventDataMap>>(eventName: Name): AsyncIterableIterator<Parameters<EventDataMap[Name]>[0]>;

	once<Name extends EventNameFromDataMap<EventDataMap>>(eventName: Name): Promise<ReturnType<EventDataMap[Name]>>;
	once<Name extends EmptyEvents>(eventName: Name): Promise<ReturnType<EventDataMap[Name]>>;

	off<Name extends EventNameFromDataMap<EventDataMap>>(eventName: Name, listener: (eventData: Parameters<EventDataMap[Name]>[0]) => void): void;
	off<Name extends EmptyEvents>(eventName: Name, listener: () => void): void;

	onAny(listener: (eventName: EventNameFromDataMap<EventDataMap> | EmptyEvents, eventData?: EventDataMap[EventNameFromDataMap<EventDataMap>]) => void): Emittery.UnsubscribeFn;
	anyEvent(): AsyncIterableIterator<[EventNameFromDataMap<EventDataMap>, EventDataMap[EventNameFromDataMap<EventDataMap>]]>;

	offAny(listener: (eventName: EventNameFromDataMap<EventDataMap> | EmptyEvents, eventData?: EventDataMap[EventNameFromDataMap<EventDataMap>]) => void): void;

	emit<Name extends EventNameFromDataMap<EventDataMap>>(eventName: Name, eventData: Parameters<EventDataMap[Name]>[0]): Promise<ReturnType<EventDataMap[Name]>>;
	emit<Name extends EmptyEvents>(eventName: Name): Promise<ReturnType<EventDataMap[Name]>>;

	emitSerial<Name extends EventNameFromDataMap<EventDataMap>>(eventName: Name, eventData: Parameters<EventDataMap[Name]>[0]): Promise<ReturnType<EventDataMap[Name]>>;
	emitSerial<Name extends EmptyEvents>(eventName: Name): Promise<ReturnType<EventDataMap[Name]>>;
}
```
