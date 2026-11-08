Create a `run` function returning a union type `E | A`
Create a `run` function returning a union type `E | A`. The code should be something like the following:
```scala 3
val result: String | Int = Raise.run {
  Raise.raise("error")
}
```
