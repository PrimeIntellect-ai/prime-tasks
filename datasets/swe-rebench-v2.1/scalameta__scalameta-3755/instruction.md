Export clause with syntax "ClassName.this.fieldName" fails to parse
Hi, I noticed this error when using Metals, but I assume this is a scalameta issue?

scalameta reports this parse error for the code below: \`.\` expected but \`outdent\` found


```Scala
case class Test():
    val name = "Test"

    case class Test2():
        export Test.this.name

@main def main(): Unit =
    val t = Test()
    val t2 = t.Test2()

    println(t.name)
    println(t2.name)
```

Even though it's a valid code that compiles and runs:

```
sbt:test_export> compile
[info] compiling 1 Scala source to /Users/user/tmp/test_export/target/scala-3.4.2/classes ...
[success] Total time: 2 s, completed 27 Jun 2024, 14.46.04
sbt:test_export> run
[info] running main
Test
Test
[success] Total time: 0 s, completed 27 Jun 2024, 14.46.06
```

Screenshot of the error:
<img width="327" alt="Screenshot 2024-06-27 at 14 58 15" src="https://github.com/scalameta/scalameta/assets/41424335/0c1924ed-f14d-46be-98e9-1605877e91be">
