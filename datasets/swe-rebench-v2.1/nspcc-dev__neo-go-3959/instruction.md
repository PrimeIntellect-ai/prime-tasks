Extend `Waiter.Wait()` with context parameter
## Is your feature request related to a problem? Please describe.
Inspired by @mialbu. `Waiter.Wait()` doesn't accept context, although `Waiter.WaitAny()` does. If user need to pass some custom cancellation context to awaiter, then he need to use `Waiter.WaitAny()` just because of the fact that `Waiter.Wait()` doesn't accept extra contexts.

## Describe the solution you'd like
Extend `Waiter.Wait()` with context parameter.

## Describe alternatives you've considered
Keep it as is, it's a matter of discussion. Opinions are welcomed.
