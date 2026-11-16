java.lang.ArithmeticException: long overflow at nrepl.bencode$read_long.invokeStatic(bencode.clj:128)
Using nrepl version 1.1.0-alpha1, when I run `clj -A:shadow-cljs watch app` against my Clojure v1.11.1 / ClojureScript v1.11.54 app, nREPL.bencode throws an ArithmeticException:

```
ERROR:
java.lang.ArithmeticException: long overflow
        at java.base/java.lang.Math.multiplyExact(Math.java:999)
        at clojure.lang.Numbers.multiply(Numbers.java:1971)
        at nrepl.bencode$read_long.invokeStatic(bencode.clj:128)
        at nrepl.bencode$read_long.invokePrim(bencode.clj)
        at nrepl.bencode$read_netstring_STAR_.invokeStatic(bencode.clj:155)
        at nrepl.bencode$read_netstring_STAR_.invoke(bencode.clj:153)
        at nrepl.bencode$read_token.invokeStatic(bencode.clj:246)
        at nrepl.bencode$read_token.invoke(bencode.clj:236)
        at nrepl.bencode$read_bencode.invokeStatic(bencode.clj:256)
        at nrepl.bencode$read_bencode.invoke(bencode.clj:253)
        at nrepl.transport$bencode$fn__22320$fn__22321.invoke(transport.clj:122)
        at nrepl.transport$bencode$fn__22320.invoke(transport.clj:122)
        at nrepl.transport$fn_transport$fn__22274.invoke(transport.clj:50)
        at clojure.core$binding_conveyor_fn$fn__5823.invoke(core.clj:2047)
        at clojure.lang.AFn.call(AFn.java:18)
        at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
        at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1136)
        at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:635)
        at java.base/java.lang.Thread.run(Thread.java:858)
ERROR:

```

I'm guessing it's some weird incompatibility, possibly related to Carmine. My deps.edn looks like this:

```
{:paths     ["src" "resources"]
 :aliases   {:nrepl       {:extra-deps {nrepl/nrepl      {:mvn/version "1.1.0-alpha1"}
                                        nrepl/drawbridge {:mvn/version "0.2.1"}}}
             :shadow-cljs {:extra-deps {thheller/shadow-cljs {:mvn/version "2.20.6"}}
                           :main-opts  ["-m" "shadow.cljs.devtools.cli"]}}
 :mvn/repos {"central" {:url "https://repo1.maven.org/maven2/"}
             "clojars" {:url "https://clojars.org/repo"}
             "google"  {:url "https://maven.google.com/"}}
 :deps      {org.clojure/clojure                {:mvn/version "1.11.1"}
             org.clojure/clojurescript          {:mvn/version "1.11.54"}

             ;; Async
             org.clojure/core.async             {:mvn/version "1.5.648"}

             ;; Streams / Async
             ;manifold/manifold          {:mvn/version "0.2.4"}

             ;; Logging
             com.taoensso/timbre                {:mvn/version "4.10.0"}

             ;; nREPL (todo alias)
             nrepl/nrepl                        {:mvn/version "1.1.0-alpha1"}

             ;; Lifecycle
             mount/mount                        {:mvn/version "0.1.16"}

             ;; Messaging
             io.nats/jnats                      {:mvn/version "2.15.3"}

             ;; Web Server
             http-kit/http-kit                  {:mvn/version "2.4.0-alpha6"}

             ;; Routing
             metosin/reitit                     {:mvn/version "0.5.18"}

             ;; Web Middleware
             ring/ring                          {:mvn/version "1.9.0"}

             throttler/throttler                {:mvn/version "1.0.1"}

             ;; Rendering
             reagent/reagent                    {:mvn/version "1.1.1"}
             rum/rum                            {:mvn/version "0.12.9"}

             ;; Wire Transport
             com.cognitect/transit-clj          {:mvn/version "1.0.329"}
             com.cognitect/transit-cljs         {:mvn/version "0.8.269"}

             ;; Data
             com.rpl/specter                    {:mvn/version "1.1.3"}

             ;; Dynamic deps at runtime
             clj-commons/pomegranate            {:mvn/version "1.2.1"}

             ;; Database
             com.google.firebase/firebase-admin {:mvn/version "9.0.0"}
             datascript/datascript              {:mvn/version "1.3.13"}
             seancorfield/next.jdbc             {:mvn/version "1.0.424"}
             org.postgresql/postgresql          {:mvn/version "42.4.0"}
             org.xerial/sqlite-jdbc             {:mvn/version "3.36.0.3"}

             ;; Caching (Redis)
             com.taoensso/carmine               {:mvn/version "3.1.0"}

             ;; Codecs
             metosin/jsonista                   {:mvn/version "0.3.5"}}}


```

## Steps to reproduce the problem

Sorry, I will try to do a minimal reproduction soon! Currently blocked on this.

## Environment & Version information

### Clojure version

1.11.1

### Java version

IBM Semeru Runtime Open Edition 18.0.2.0 (build 18.0.2+9)

### Operating system

macOS Monterey 12.4

### Additional contract requirements

- When the nREPL bencode transport receives malformed or non-bencode input, including a numeric token too large to represent as a signed 64-bit integer, it must fail with an exception whose message identifies the input as invalid, rather than exposing `ArithmeticException: long overflow`.
- A decoded top-level value must be a map. Reject other top-level values with `clojure.lang.ExceptionInfo` whose message is `nREPL message must be a map.`
