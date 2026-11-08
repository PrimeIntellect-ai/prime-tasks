allow explicit `regexp` in filter arguments
Currently, using strings for filtering in the `filter()` function implements a pseudo-syntax, where `*` is used as wildcard and other regexp-arguments are escaped to have a "close-to-string" user experience. Hpwever, for expert users, we should add a feature to explicitly allow regexp (i.e., do not use the pseudo-syntax in teh `pattern_match()`).
