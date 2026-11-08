A colon isn't recognized as a valid character in a symbol
I occasionally like to use colons as an ad hoc namespacing facility when I'm naming vars. Clojure allows this:

```
Clojure 1.10.0
user=> (defn foo:bar [x]
         (* 2 x))
#'user/foo:bar
user=> (foo:bar 3)
6
```

clojure-lsp's definition of a valid symbol doesn't seem to include colons (and perhaps other rare symbols?)

![2020-01-14-123325_541x204_scrot](https://user-images.githubusercontent.com/4909079/72367518-507ec380-36ca-11ea-88c9-86b06f757960.png)
