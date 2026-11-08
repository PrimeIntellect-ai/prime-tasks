JS backend: Array.toList drops first element
Executing `.toList` on an array drops the first element.

## Example
For the program:
```effekt
import mutable/array

def main() = {
  val array = arrayFromList([1,2,3]);
  println(array.toList)
}
```
we get the output:
```
Cons(2, Cons(3, Nil()))
```
