Namespace linter
#547 implements a `missing_package_linter()` which checks if all packages loaded by `library()`, `require()`, `loadNamespace()`, and `requireNamespace()` are installed.

Apart from that, we could also check the usage of `ns::obj` and `ns:::obj` as they also used to access objects in a namespace (provided by package).

We could implement a separate linter (as suggested at https://github.com/jimhester/lintr/pull/547#issuecomment-719822505) to check if

1. The package `ns` in `ns::obj` and `ns:::obj` are installed.
2. The `obj` in `ns::obj` is exported from namespace `ns`.
3. The `obj` in `ns:::obj` exists in namespace `ns`.

While checking 1 does not load any new package, checking 2 and 3 might load the package being checked. I'm not sure if we allow loading extra packages from user code?
