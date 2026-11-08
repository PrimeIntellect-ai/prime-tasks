3.8.0 breaks lambda functions
The latest scalafmt 3.8.0 break lila code:

https://github.com/lichess-org/lila/pull/14717

## Steps

Given code like this:
```scala
  val top10NbGame = mongoCache.unit[List[User.LightCount]](
    "user:top:nbGame",
    74 minutes
  ): loader =>
    _.refreshAfterWrite(75 minutes).buildAsyncFuture:
      loader: _ =>
        userRepo topNbGame 10 dmap (_.map(_.lightCount))
```

## Problem

Scalafmt formats code like this:
```scala
  val top10NbGame = mongoCache.unit[List[User.LightCount]](
    "user:top:nbGame",
    74 minutes
  ): loader =>
    _.refreshAfterWrite(75 minutes).buildAsyncFuture:
      loader: _ => userRepo topNbGame 10 dmap (_.map(_.lightCount))
```

## Expectation

I would like scalafmt doesn't change the code as it breaks the build

## Notes

I breaks other similar code as well, please check the PR link for more details.

### Additional contract requirements

The code in the Steps section must not be transformed in a way that breaks the build. The observable behaviour is the syntax tree produced by parsing that code: the `loader` parameter of the outer lambda must have no declared type, and the `_ => ...` expression that follows the colon must be the body of the lambda passed to `loader`. The colon must not be parsed as a type ascription.
