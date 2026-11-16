Lazy given
## Configuration (required) ##

```
version = 3.7.17
runner.dialect = scala3
```

## Command-line parameters (required) ##

When I run scalafmt via CLI like this: `scalafmt -c .scalafmt.conf Given.scala`

## Steps

Given code like this:
```scala
lazy given endpoint: DcEndpoint = TestChatServer.start()
```

## Problem

Scalafmt formats code like this:
```scala
error: [dialect scala3] lazy not allowed here. Only vals can be lazy
lazy given endpoint: DcEndpoint = TestChatServer.start()
```

## Expectation

I would like the formatted output to look like this:
```scala
lazy given endpoint: DcEndpoint = TestChatServer.start()
```

## Workaround

Exclude files like this.

### Additional contract requirements

- For `trait Foo { protected[this] lazy var from: Int }`, the parser must report exactly `lazy not allowed here. Only val/given can be lazy`.
- Parsing `lazy given endpoint: DcEndpoint = TestChatServer.start()` must succeed and produce a `scala.meta.Defn.GivenAlias` whose modifier list contains `scala.meta.Mod.Lazy`.
