Cyclic imports make the interpreter loop
**Describe the bug**
Cyclic imports make the binary overflow its stack. It's not evaluation, as it already happens just with typechecking. Spotted because of #407.

**To Reproduce**

```
echo 'let x = import "b.ncl" in null' > a.ncl
echo 'let x = import "c.ncl" in x' > b.ncl
echo 'let x = import "b.ncl" in x' > c.ncl
nickel -f a.ncl typecheck
```

**Expected behavior**
The program should evaluate successfully on `null`. Cyclic imports shouldn't be a problem. They weren't originally.

**Environment**
 - OS name + version: Linux 5.10.0-8-amd64 SMP Debian 5.10.46-4 (2021-08-03) x86_64 GNU/Linux
 - Version of the code: 269ead2a58ded6b1939e70dcd23550e92304277f

**Additional context**

A git bisect shows that the offending commit is b029763736dfa954e82bc65370b35c24117f6848
cc @francois-caddet
