Day 43
Good morning! Here's your coding interview problem for today.

This problem was asked by Amazon.

Implement a stack that has the following methods:

`push(val)`, which pushes an element onto the stack
`pop()`, which pops off and returns the topmost element of the stack. If there are no elements in the stack, then it should throw an error or return null.
`max()`, which returns the maximum value in the stack currently. If there are no elements in the stack, then it should throw an error or return null.

_Each method should run in constant time._

### Additional contract requirements

- The stack is provided in package `day43`.
- A public interface `MaxIntStack` exposes the methods `Push(val int)`, `Pop() (int, error)` and `Max() (int, error)`.
- A public function `NewMaxIntStack() MaxIntStack` returns a fresh, ready-to-use stack.
- A public function `StackEmptyError() error` returns the shared sentinel error value that `Pop` and `Max` return when the stack is empty; callers may compare a returned error against it.
