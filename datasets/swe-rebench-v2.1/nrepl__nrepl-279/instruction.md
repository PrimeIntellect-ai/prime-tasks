nrepl transports should `read` with `[HIDDEN]` options
Had an issue come up in inf-clojure. We ask for arglists with the following form:

```clojure
(try
  (:arglists
   (clojure.core/meta
     (clojure.core/resolve
       (clojure.core/read-string \"%s\"))))
  (catch #?(:clj Throwable :cljr Exception) e nil))
```

Someone is using nrepl's transport/tty on a Clojure repl and it is blowing up on the reader conditional.

The reader conditional exists because cljr is on .NET and has no notion of `Throwable`.  There are a few ways to fix this in inf-clojure:
- just collapse back to catching `Exception` for both branches and thus remove the need for conditional reading
- fully disentangle the new branches and make a new interaction layer for cljr vs "regular" clj on the jvm
- have nrepl allow reader conditionals.

The last choice would be the most work, but I think it is the most correct. Prior art for why this is correct:
- clojure's socket repl allows for reader conditionals by default: https://github.com/clojure/clojure/blob/master/src/clj/clojure/core/server.clj#L174
- clojure's main repl allows reader conditionals as well: https://github.com/clojure/clojure/blob/master/src/clj/clojure/main.clj#L168

That is a strong argument that arbitrary repls aught to default to allowing reader conditionals in general.

[HIDDEN]

And it appears nrepl's default bencode transport allows for reader conditionals:

```clojure
❯ lein repl
nREPL server started on port 61122 on host 127.0.0.1 - nrepl://127.0.0.1:61122
REPL-y 0.5.1, nREPL 0.8.3
Clojure 1.10.3
OpenJDK 64-Bit Server VM 17.0.1+12-LTS
    Docs: (doc function-name-here)
          (find-doc "part-of-name-here")
  Source: (source function-name-here)
 Javadoc: (javadoc java-object-or-class-here)
    Exit: Control+D or (exit) or (quit)
 Results: Stored in vars *1, *2, *3, an exception in *e

user=> (+ 1 #?(:clj 2))
3
user=>
```

### Additional contract requirements

- The TTY transport must read Clojure forms containing reader conditionals and select the branch applicable to the current platform rather than fail during reading.
