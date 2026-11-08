Hot-loading dependencies sample doesn't work in lein
## Expected behavior
The pomegranate [hot-loading dependencies](https://nrepl.org/nrepl/usage/misc.html) sample (for `clj`) should also work in `lein`.

## Actual behavior
The dependency gets added without error to some classloader, but isn't available to `require`. It's visible as a resource.
```
PS C:\Users\Jack\SSD\Projects\classloaders-201> lein run -m nrepl.cmdline --interactive
nREPL server started on port 53374 on host 127.0.0.1 - nrepl://127.0.0.1:53374
nREPL 0.5.3
Clojure 1.10.0
Java HotSpot(TM) 64-Bit Server VM 10.0.1+10
Interrupt: Control+C
Exit:      Control+D or (exit) or (quit)
user=> (require 'bidi.bidi)
Execution error (FileNotFoundException) at user/eval1282 (form-init11955807739262716208.clj:1).
Could not locate bidi/bidi__init.class, bidi/bidi.clj or bidi/bidi.cljc on classpath.
user=> (require '[cemerick.pomegranate :as pg])
nil
user=> (pg/add-dependencies :coordinates '[[bidi "2.1.5"]]
                     :repositories (merge cemerick.pomegranate.aether/maven-central {"clojars" "https://clojars.org/repo"}))
{[bidi "2.1.5"] #{[prismatic/schema "1.1.7" :exclusions [[org.clojure/tools.reader]]]}, [prismatic/schema "1.1.7" :exclusions [[org.clojure/tools.reader]]] nil}
user=> (require 'bidi.bidi)
Execution error (FileNotFoundException) at user/eval1756 (form-init11955807739262716208.clj:1).
Could not locate bidi/bidi__init.class, bidi/bidi.clj or bidi/bidi.cljc on classpath.
user=> (.getResource (.getContextClassLoader (Thread/currentThread)) "bidi/bidi.cljc")
#object[java.net.URL 0x93a1078 "jar:file:/C:/Users/Jack/.m2/repository/bidi/bidi/2.1.5/bidi-2.1.5.jar!/bidi/bidi.cljc"]
user=>
```

## Steps to reproduce the problem
Example project: https://github.com/jc776/classloaders-201, then follow REPL session above
It is possible to get the dependency to load by bringing back some additional behaviour that was in cemerick/pomegranate#102 but never merged, which was closed in favour of nrepl/nrepl#35 - see project's README.

## Environment & Version information
- lein 2.8.3, nREPL 0.5.3
- Clojure 1.10.0
- (Oracle) Java 10
- Windows 10
