Process fails with "Method code too large!" when it encounters protocol with a lot of methods
I'm running into `Method code too large!` failures when Eastwood encounters a `defprotocol` that compiles fine normally. The protocol has 22 methods, so it's on the larger side but still real-world.

Here's the stacktrace

```
RuntimeException Method code too large!
    clojure.asm.MethodWriter.getSize (MethodWriter.java:1872)
    clojure.asm.ClassWriter.toByteArray (ClassWriter.java:775)
    clojure.lang.Compiler$ObjExpr.compile (Compiler.java:4585)
    clojure.lang.Compiler$FnExpr.parse (Compiler.java:4049)
    clojure.lang.Compiler.analyzeSeq (Compiler.java:6866)
    clojure.lang.Compiler.analyze (Compiler.java:6669)
    clojure.lang.Compiler.eval (Compiler.java:6924)
    clojure.lang.Compiler.eval (Compiler.java:6890)
    clojure.core/eval (core.clj:3105)
    clojure.core/eval (core.clj:3101)
    eastwood.copieddeps.dep2.clojure.tools.analyzer.jvm/analyze+eval/fn--3627 (jvm.clj:521)
    eastwood.copieddeps.dep2.clojure.tools.analyzer.jvm/analyze+eval (jvm.clj:521)
    eastwood.copieddeps.dep2.clojure.tools.analyzer.jvm/analyze+eval (jvm.clj:473)
    eastwood.copieddeps.dep2.clojure.tools.analyzer.jvm/analyze+eval/fn--3625 (jvm.clj:504)
    clojure.core/mapv/fn--6953 (core.clj:6627)
    clojure.lang.ArrayChunk.reduce (ArrayChunk.java:63)
    clojure.core.protocols/fn--6750 (protocols.clj:136)
    clojure.core.protocols/fn--6750 (protocols.clj:124)
    clojure.core.protocols/fn--6710/G--6705--6719 (protocols.clj:19)
    clojure.core.protocols/seq-reduce (protocols.clj:31)
    clojure.core.protocols/fn--6736 (protocols.clj:75)
    clojure.core.protocols/fn--6736 (protocols.clj:75)
    clojure.core.protocols/fn--6684/G--6679--6697 (protocols.clj:13)
    clojure.core/reduce (core.clj:6545)
    clojure.core/mapv (core.clj:6618)
    clojure.core/mapv (core.clj:6618)
    eastwood.copieddeps.dep2.clojure.tools.analyzer.jvm/analyze+eval (jvm.clj:504)
    eastwood.copieddeps.dep2.clojure.tools.analyzer.jvm/analyze+eval (jvm.clj:473)
    eastwood.analyze-ns/analyze-file/fn--4288/fn--4290 (analyze_ns.clj:288)
    eastwood.analyze-ns/analyze-file/fn--4288 (analyze_ns.clj:286)
    eastwood.analyze-ns/analyze-file (analyze_ns.clj:284)
    eastwood.analyze-ns/analyze-file (analyze_ns.clj:219)
    eastwood.analyze-ns/analyze-ns (analyze_ns.clj:337)
    eastwood.analyze-ns/analyze-ns (analyze_ns.clj:315)
    eastwood.lint/lint-ns (lint.clj:600)
    eastwood.lint/lint-ns (lint.clj:592)
    eastwood.lint/eastwood-core/fn--6582 (lint.clj:1077)
    eastwood.lint/eastwood-core (lint.clj:1076)
    eastwood.lint/eastwood-core (lint.clj:993)
    eastwood.lint/eastwood (lint.clj:1194)
    eastwood.lint/eastwood (lint.clj:1175)
    eastwood.lint/eastwood-from-cmdline (lint.clj:1207)
    eastwood.lint/eastwood-from-cmdline (lint.clj:1206)
    clojure.lang.Var.invoke (Var.java:379)
    eastwood.versioncheck/run-eastwood (versioncheck.clj:15)
    eastwood.versioncheck/run-eastwood (versioncheck.clj:9)
    user/eval21 (form-init6943476413789013398.clj:1)
    user/eval21 (form-init6943476413789013398.clj:1)
    clojure.lang.Compiler.eval (Compiler.java:6927)
    clojure.lang.Compiler.eval (Compiler.java:6917)
    clojure.lang.Compiler.load (Compiler.java:7379)
    clojure.lang.Compiler.loadFile (Compiler.java:7317)
    clojure.main/load-script (main.clj:275)
    clojure.main/init-opt (main.clj:277)
    clojure.main/init-opt (main.clj:277)
    clojure.main/initialize (main.clj:308)
    clojure.main/null-opt (main.clj:342)
    clojure.main/null-opt (main.clj:339)
    clojure.main/main (main.clj:421)
    clojure.main/main (main.clj:384)
    clojure.lang.Var.invoke (Var.java:383)
    clojure.lang.Var.applyTo (Var.java:700)
    clojure.main.main (main.java:37)

```

[I've isolated the statement triggering the bug in a separate project here](https://github.com/camsaul/eastwood-fail-demo) if it's any help looking into the issue.

``` bash
$ lein eastwood
```

will trigger the error.
