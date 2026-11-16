track(event:properties:) takes [String:Any], but screen(screenTitle:properties:) takes [Any:Hashable]
**Describe the bug**
There's a bit of mismatch/asymmetry between the various `track` and `screen` methods. Namely, `track(event:properties:)` takes `[String:Any]`, but `screen(screenTitle:properties:)` takes [Any:Hashable]`.

**Expected behavior**
I'd expect these to take the same thing, unless there's some reason they can't.

**Platform (please complete the following information):**
 - Library Version in use: 1.0.2
 - Platform being tested: [e.g. iOS]

### Additional contract requirements

`screen(screenTitle:properties:)` must accept the same properties dictionary type as `track(event:properties:)`: `[String: Any]`. This permits screen properties to contain heterogeneous values, including arrays.
