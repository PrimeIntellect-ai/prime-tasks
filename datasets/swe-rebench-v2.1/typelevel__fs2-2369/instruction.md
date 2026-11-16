A variant of debounce/metered that begins immediately
I found it surprising that metered/debounce doesn't immediately "start". Think of debouncing a button - You probably want to react immediately to the event instead of waiting for the whole debounce period to finish. Similarly for things like polling, you want to start immediately.

I can achieve this with [HIDDEN], but I feel like this is a common enough pattern for it to be an alternative method? e.g. `meteredStartImmediate`

Or at least documented. WDYT?

```
import cats.effect._
import fs2._

import scala.concurrent.duration._

object FixmeFs2Main extends IOApp {
  override def run(args: List[String]): IO[ExitCode] =
    [HIDDEN]
}
```
^ @SystemFw FYI. I think this works.

### Additional contract requirements

- Add a public method `meteredStartImmediately(rate: FiniteDuration)` on `Stream` in `fs2` that requires an implicit `Temporal[F]` capability and returns a `Stream[F, O]`.
- The returned stream emits the first element of the original stream immediately, then continues to emit subsequent elements spaced by `rate`. It preserves the original stream’s elements and their order.
