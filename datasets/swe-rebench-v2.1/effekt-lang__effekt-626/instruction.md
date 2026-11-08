Allow braces in a pattern match
When an arm of an pattern match gets too long, I'd like to wrap it in _braces_:
```scala
def main(opt: Option[Int]) = {
  opt match {
    case None() => println("Nothing")
    case Some(x) => {
      println("We have a number: ${x.show}")
    }
  }
}
```

Unfortunately, the parser doesn't like that very much:
<img width="418" alt="Screenshot 2024-03-22 at 11 26 18" src="https://github.com/effekt-lang/effekt/assets/11269173/1b9c7ef3-0e4f-4ca5-b4c1-bac4e4df94eb">

(As far as I know, this is one of the few places where we only allow delimiting by `case`)
