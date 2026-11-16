Backport PEP 695's TypeAliasType
Cross-referencing here for visibility.

https://discuss.python.org/t/please-consider-delaying-or-even-rejecting-pep-695/26408/62?u=adriangb
https://mail.python.org/archives/list/typing-sig@python.org/thread/T5MRLQL7H4Y4HWFA7CBC34MHJCKQEI7L/

cc @JelleZijlstra, I didn't want to bug everyone in the discuss thread 😅

### Additional contract requirements

`TypeAliasType` must be constructible with a name and underlying value, and accept an optional `type_params` argument for generic aliases. A created alias exposes its name as `__name__`, its underlying value as `__value__`, and its declared type parameters as `__type_params__`.
