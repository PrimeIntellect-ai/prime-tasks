Add a new strategy to map logical typed-error without using the `withError` function
The `withError` function lets us use errors from different hierarchies in the same scope. See the following tweet for an example:

https://x.com/riccardo_cardin/status/1783803145111351797

However, it adds a lot of complexity to the code since the happy path is mixed up with the code for the type transformation of the error channel.

Implement a new _strategy_ called `RaiseMap` that enables us to do something similar to the following:

```scala
class Users(repo: UserRepository) {
    given RaiseMap[NetworkError, UserNotFound] = error => UserNotFound
    def findUserById(id: String): User raises UserNotFound =
      val user = repo.findById(id)
      user
}
```

### Additional contract requirements

The strategy is exposed under the public name `MapError`, not `RaiseMap`: it is a public trait `MapError[From, To]` in `in.rcard.raise4s.Strategies`. The `RaiseMap` name in the example above is superseded by `MapError`. It is a `Raise[From]`, so an instance can be provided as a `given` and used wherever a `Raise[From]` is required. It declares:

- `def map(error: From): To`: converts an error of type `From` into an error of type `To`.
- `def raise(error: From): Nothing`: raises the error obtained by applying `map` to the given error.

A `MapError[From, To]` instance can be created from a function for `map`, for example `given MapError[String, Int] = error => error.length`.
