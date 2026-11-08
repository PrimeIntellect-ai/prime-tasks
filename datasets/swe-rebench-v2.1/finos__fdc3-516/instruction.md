All DesktopAgent and Channel APIs should be async
## Enhancement Request
The majority of DesktopAgent and Channel API calls are async, with the exception of:
- `fdc3.broadcast` & `channel.broadcast`
- `fdc3.addIntentListener`
- `fdc3.addContextListener` & `channel.addContextListener`
- `fdc3.getInfo`

Make all API functions async for consistency, safety and ease of use.

### Use Case:
The inconsistency described above makes using these functions slightly different from the other API calls by:
- adding complexity to code
  - for example see the differences in the implementation of the [fdc3 NPM module's wrappers for the desktop agent functions](https://github.com/finos/FDC3/blob/7ffe04bf31eceb4a089cc309b0901b772fa81837/src/api/Methods.ts#L46-L56), where exceptions are thrown, rather than a rejected promise returned. This prevented the module from integrating fdc3Ready event support into all functions.
  - However, as async functions used with `await` will convert rejected promises into exceptions this behaviour can still be achieved after this change is made.
- Failing to acknowledge that most implementations of these functions will be asynchronous anyway (as they will often communicate with other windows or services in a container)
  - by making these functions synchronous we make it harder for a DesktopAgent implementation to return *after* completing the operation, so that we can be sure a listener has been added or a broadcast is completed before we move onto the next activity. Hence, we risk causing race conditions that could otherwise be prevented by an implementation by resolving/rejecting promise once the action is completed.

### Supporting info
Making these functions async will change their return types (wrapping the return type in a Promise), hence this is a breaking change. However, it's a limited one because:
- Existing behaviour can be achieved in an async function by prefixing the calls with `await`
- The `broadcast` function has no return type currently, hence making these async will change nothing for most implementations (as you don't need to add the `await` keyword for existing code to continue working as it always has done).
- The `addContextListener` and `addIntentListener` functions only return Listener objects that are used to unsubscribe the listeners. In our experience, these are used only in the minority of implementations, hence, the change will not affect most implementations (as above).
- `getInfo()` is new in 1.2 and usage is not yet widespread.
