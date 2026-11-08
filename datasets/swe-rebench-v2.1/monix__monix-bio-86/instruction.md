Implement BIO.map2 ... map6 from Monix Task
Please put the method in other companion objects as well (`Task`, `UIO`) with appropriate return type if it applies

General flow:
- Comment in this issue to let others know that someone is working on it
- [HIDDEN]
- Modify signature to take advantage of typed errors if possible
- Implementation might require some changes, in most cases the compiler should guide you, also look for already ported operators for inspiration. The most common change is to use `BiCallback` instead of `Callback` to be able to signal errors on two different channels ("typed" channel and hidden channel for "fatal" errors).
- Copy the corresponding tests from Monix. Try to use `BIO` instead of `Task` with `E` different than `Throwable` when possible to uncover any possible bugs in the internals.
- If you test for a failure, try to test for both "expected" failure (error from `E`, it will be `CancelableFuture(Left))` after `runToFuture`) and "fatal" failure (it will be a failed `CancelableFuture`).
- Take a look at the existing tests to see if there aren't any commented ones using newly implemented function and uncomment them.

Don't be shy to ping me if you need any advice or want to consult the solution. I really appreciate the involvement and I'm happy to help!

### Additional contract requirements

- Provide `BIO.map2` through `BIO.map6`, and corresponding methods on `Task` and `UIO` where applicable. Each combines successful input values with the supplied mapping function and has the appropriate return type.
- Evaluate inputs strictly in argument order, stopping at the first failure without evaluating later inputs. Propagate typed failures as `Left(E)` and fatal exceptions as failed futures; apply the mapping function only when all inputs succeed.
