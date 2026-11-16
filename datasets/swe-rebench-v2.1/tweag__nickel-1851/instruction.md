The LSP doesn't show the details of type errors anymore in the diagnostics
**Describe the bug**
When I edit a file with a static type error in it, the diagnostic shown in my editor is not very informative, because it doesn't show the notes of the diagnostic which include the type and whatnot. I thus just get "incompatible types", which is unhelpful. This is a regression wrt to latest stable (1.4.1), which does show the full diagnostic (see below).

**To Reproduce**
Input `5 : String` in your editor:

![image](https://github.com/tweag/nickel/assets/6530104/f724c48e-625a-428a-b0dc-40826657bb6c)

**Expected behavior**

This is the behavior in current stable (1.4.1), and expected one:

![image](https://github.com/tweag/nickel/assets/6530104/3a21727e-67c4-4d89-9bd9-3b3a66c69e3f)

**Environment**
 - Version of the code: 71a84b3ed9226379b24aa55cc6e1149fd8ec212d

### Additional contract requirements

- For the input `5 : String`, the diagnostic message must be exactly:

```
incompatible types
Expected an expression of type `String`
Found an expression of type `Number`
These types are not compatible
```
