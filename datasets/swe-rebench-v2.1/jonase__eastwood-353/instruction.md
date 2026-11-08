False positive "Namespace is never used"
When importing a class defined in another namespace with `defrecord`, it is necessary to first `require` the namespace so that the class is compiled before it can be imported (see https://clojuredocs.org/clojure.core/defrecord#example-542692d2c026201cdc326f87), but eastwood warns that the required namespace is never used.
