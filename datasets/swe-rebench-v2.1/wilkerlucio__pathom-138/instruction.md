::p/reader-error instead of ::p/not-found for transitive resolvers
In this case

```clojure
(defresolver test-x [_ _]
  {::pc/input  #{}
   ::pc/output [:x]}
  {})
(defresolver test-y [_ _]
  {::pc/input  #{:x}
   ::pc/output [:y]}
  {:y true})
```

`(parser {} [:y])` with `reader2` returns `{:y ::p/reader-error}` instead of `{:y ::p/not-found}`, while parser with `parallel-reader` returns what's expected.

Quick repro (v2.2.28):
```clojure
(let [register [(pc/resolver `x1
                             {::pc/output [:x1]}
                             (fn [env input] {:x1 nil}))
                (pc/resolver `x2
                             {::pc/output [:x2]}
                             (fn [env input] {}))
                (pc/resolver `y1
                             {::pc/input  #{:x1}
                              ::pc/output [:y1]}
                             (fn [env {:keys [x1]}] {:y1 (pr-str x1)}))
                (pc/resolver `y2
                             {::pc/input  #{:x2}
                              ::pc/output [:y2]}
                             (fn [env {:keys [x2]}] {:y2 (pr-str x2)}))]
      parser (p/parallel-parser {::p/plugins [(pc/connect-plugin {::pc/register register})
                                              p/error-handler-plugin]})
      env {::p/reader [p/map-reader
                       pc/reader2
                       pc/open-ident-reader]}]
  (async/<!! (parser env [:y1 :y2])))
```

Output:
```clojure
{:y1 "nil",
 :y2 :com.wsscode.pathom.core/reader-error,
 :com.wsscode.pathom.core/errors {[:y2] "class clojure.lang.ExceptionInfo: Insufficient resolver output - {:com.wsscode.pathom.parser/response-value {}, :key :x2}"}}
```

### Additional contract requirements

When `pc/reader2` is used by a parallel parser, a downstream resolver whose prerequisite resolver does not provide a required value must produce `::p/not-found`, not `::p/reader-error`.
