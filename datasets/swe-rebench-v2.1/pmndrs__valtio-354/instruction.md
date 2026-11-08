Bug with history (again?)
Hello again, I think I found something.

[sandbox link](https://codesandbox.io/s/react-typescript-forked-6leim?file=/src/App.tsx)

I'm trying to implement transition (jump) between different states in my project and found one issue.

If I try to undo or redo a state in a loop it doesn't work as expected.

PS: Loop is just an example for this issue, I know I can get the value directly from the snapshots array.

Expected:
Case 1:
initial value 0
UpdateValue (x3) -> undo by step (x3) -> redo by step (x3) -> 3

Case 2:
initial value 0
UpdateValue (x3) -> undo all -> redo all -> 3

-----------------------------------------------------------------------------

Actual:
Case 1:
initial value 0
UpdateValue (x3) -> undo by step (x3) -> redo by step (x3) -> 3        <- fine

Case 2:
initial value 0
UpdateValue (x3) -> undo all -> redo all -> 0                                          <- bad
