metac is fragile on JDK 11 (URLClassLoader/app class loader)
One of the changes in JDK 11 is that the application classloader isn't a `URLClassLoader`, see https://blog.codefx.org/java/java-11-migration-guide/#Casting-To-URL-Class-Loader.

While looking at https://scalameta.org/docs/semanticdb/guide.html#installation, I switch the instructions to use Coursier's sexy, new `cs` launchers, and found it to blow up because I was using JDK 11:

```bash
$ cs launch org.scalameta:metac_2.13.1:4.3.0 -- -cp $(cs fetch -p org.scala-lang:scala-library:2.13.1) Test.scala
Exception in thread "main" java.lang.RuntimeException: unsupported classloader: jdk.internal.loader.ClassLoaders$AppClassLoader@6ff3c5b5
	at scala.sys.package$.error(package.scala:27)
	at scala.meta.internal.metac.Main.process(Main.scala:23)
	at scala.meta.cli.Metac$.process(Metac.scala:36)
	at scala.meta.cli.Metac$.process(Metac.scala:27)
	at scala.meta.cli.Metac$.main(Metac.scala:10)
	at scala.meta.cli.Metac.main(Metac.scala)
```

I opened the issue in Coursier (https://github.com/coursier/coursier/issues/1572) and found out it's also possible to blow it up with the old launcher, by making it spawn a new JVM:

```bash
$ coursier launch --fork org.scalameta:metac_2.13.1:4.3.0 -- -cp $(coursier fetch -p org.scala-lang:scala-library:2.13.1) Test.scala
Exception in thread "main" java.lang.RuntimeException: unsupported classloader: jdk.internal.loader.ClassLoaders$AppClassLoader@6ff3c5b5
	at scala.sys.package$.error(package.scala:27)
	at scala.meta.internal.metac.Main.process(Main.scala:23)
	at scala.meta.cli.Metac$.process(Metac.scala:36)
	at scala.meta.cli.Metac$.process(Metac.scala:27)
	at scala.meta.cli.Metac$.main(Metac.scala:10)
	at scala.meta.cli.Metac.main(Metac.scala)
```

(There's also a few more references to URLClassLoader in the repo: https://github.com/scalameta/scalameta/search?q=URLClassLoader.)

### Additional contract requirements

- `metac` must process a Scala source when it runs on a JVM whose application classloader is not a `URLClassLoader` (for example JDK 11+ launched with `java -cp ...`), instead of failing with an "unsupported classloader" error.
- `metacp --usejavacp` must locate the scala-library on the JVM class path and process it when the application classloader is not a `URLClassLoader`, instead of failing.
