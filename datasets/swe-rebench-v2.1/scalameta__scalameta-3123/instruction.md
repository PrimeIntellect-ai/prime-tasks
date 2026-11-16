[dialect scala3] outdent expected but } found
## Configuration (required) ##


Please paste the contents of your `.scalafmt.conf` file here:
```
version = "3.7.3"
runner.dialect = scala3
```

## Command-line parameters (required) ##

I ran scalafmt via CLI like this: `./scalafmt-native`

## Steps

Given code like this:
```scala
object Hello {
  val fun = () =>
    if (true) {
      new Object { obj =>
        println(toString)
      }
    }

  def main(args: Array[String]): Unit = fun()
}
```
in file `Hello.scala`.

## Problem

Scalafmt fails with `Hello.scala:10: error: [dialect scala3] outdent expected but } found` on the last `}`.

## Expectation

It should work as this code compiles and run fine.

## Workaround

Put `println(toString)` in a block like: `{ println(toString) }` or put it on the same line as `obj`.

## Notes

The error does not happen if we comment `obj =>` or if we remove the block of the `if` or if we do not put it in `fun`.
