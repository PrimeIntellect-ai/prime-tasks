Bug with history?
Bug with history or I just don't understand how it should work.

[sandbox link](https://codesandbox.io/s/react-typescript-forked-m0s2f?file=/src/App.tsx)

After a few clicks of undo, it just stops working.

Expected:
initial value 0
add -> undo -> add -> add -> add -> undo -> undo -> undo -> add -> add -> undo -> undo -> 0


Actual:
initial value 0
add -> undo -> add -> add -> add -> undo -> undo -> undo -> add -> add -> undo -> undo -> 3
