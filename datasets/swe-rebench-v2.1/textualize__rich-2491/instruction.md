[REQUEST] Add `max_depth` as a parameter to `install()`
**How would you improve Rich?**

Currently `rich.pretty.install()` accepts most of the parameters allowed by `rich.pretty.pprint()`, but it doesn't have `max_depth`. I would add this parameter to `install()`.

**What problem does it solve for you?**

I would like to use the rich install hook, but also to customize the pretty printing behaviour, specifically the `max_depth` argument to simplify the result presentation. It isn't trivial to implement this in user code, because the `install()` function is actually quite complex, and difficult to modify.
