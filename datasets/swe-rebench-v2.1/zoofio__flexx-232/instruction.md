Generic way to avoid object deletion for properties that are a list of Models
Properties on `class Both` that are a list of Model instances, need some extra care to avoid deletion of the model objects. The reason is that "jitter" of the property when it is set from both Python and JS (e.g. during initialization) causes the property to fluctuate, making the objects go out of scope, being cleaned up by the GC, and subsequently deleted in JS as well.

One example of such a case is the `children` and `parent` property of `ui.Widget`.

The current solution is to explicitly keep the objects alive for a set amount of time when the property is set, using a simple "liveKeeper" object. However, there are other cases where such an approach would be needed, and having to implement such a thing feels hacky.

Ideally, Flexx would be able to handle this in an automatic way. If that is unfeasible, perhaps there is a more streamlined approach to help circumvent this problem.
