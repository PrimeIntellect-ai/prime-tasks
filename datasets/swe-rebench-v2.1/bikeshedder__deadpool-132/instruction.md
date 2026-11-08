Add status information to the managed Object wrapper
Interesting data for statistics could be:

- creation_timestamp
- last_usage
- recycle_count

These could be made available via a `Object::status(this: Self) -> ObjectStatus` method

### Additional contract requirements

- The managed `Object` wrapper exposes its statistics through a public method `Object::statistics(this: &Self) -> Metrics` in the `deadpool::managed` module.
- `Metrics` is a public struct in the `deadpool::managed` module with the following public fields:
  - `created: std::time::Instant` - the instant when the object was created.
  - `recycled: Option<std::time::Instant>` - the instant when the object was last recycled, or `None` if it has never been recycled.
  - `recycle_count: usize` - the number of times the object has been recycled.
- The `PostRecycle` hook trait method `post_recycle` receives a `&Metrics` reference describing the object being recycled, in addition to the mutable object: `async fn post_recycle(&self, obj: &mut M::Type, metrics: &Metrics) -> Result<(), HookError<M::Error>>`.
