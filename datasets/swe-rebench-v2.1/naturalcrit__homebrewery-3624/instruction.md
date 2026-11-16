Markdown: Functions break if a variable name is a substring of the function names
### Your idea:

During development of #3587, I discovered that `abs(a)` did not work, but `abs(c)` did.

Exhaustive testing for `abs()`:
![image](https://github.com/user-attachments/assets/cb4593b2-5c46-4947-b31b-13a088e29240)

Initial testing for `floor()`:
![image](https://github.com/user-attachments/assets/b470d596-7b85-4ddc-ba89-06b9d58a9adb)

As can be seen, in every case where a variable name used in that calculation is a substring of the function name, the function stops working.

My suspicion is that the issue lies here, `shared/naturalcrit/markdown.js:line 465`:
![image](https://github.com/user-attachments/assets/098bcb91-5a8a-467b-b585-497fb215692f)

[HIDDEN]

### Additional contract requirements

- Math expressions should evaluate correctly when a variable name is a substring of a function name, including the reported `abs(a)` case.
- Substituting a variable must not alter a distinct variable occurrence merely because its name contains the substituted variable name; each variable reference should resolve according to its full name.
