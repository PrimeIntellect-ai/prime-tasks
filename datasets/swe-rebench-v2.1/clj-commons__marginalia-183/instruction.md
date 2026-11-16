Processing reader conditionals broken
I see from #103 that `cljc` should now be fixed now. However, I'm still not able to generate documentation for https://github.com/metasoarous/semantic-csv (try executing the `./build_docs.sh` script), and get the following error:

```
Exception in thread "main" java.lang.RuntimeException: Problem parsing near line 1 <(:clj [clojure.java.io :as io])> original reported cause is java.lang.RuntimeException: Conditional read not allowed -- java.lang.RuntimeException: Conditional read not allowed, compiling:(/tmp/form-init9194388453733717094.clj:1:73)
        at clojure.lang.Compiler.load(Compiler.java:7442)
        ...
```

Any updates on this?
