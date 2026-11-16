Consider building upstream modules regardless of being changed or not when using -pl and -am
See https://github.com/vackosar/gitflow-incremental-builder#mvn--pl:

> - Upstream projects of these selected projects are built if:
>   - `-am` (`--also-make`) is used
>   - _and_:
>     - they are **changed** (or depend on other changed upstream modules) _and_ [`buildUpstream`](#gibbuildUpstream) is _not_ `never` or `false`
>     - _or_ [`buildAll`](#gibbuildall) is enabled

More specifically this part:
> they are **changed** (or depend on other changed upstream modules)

I had a reason to implement it like this but I don't remember. Actually I now think this is counterintuitive and the condition should be dropped.
