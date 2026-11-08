Compiler crash when checking exhaustiveness of a pattern on a type with duplicate variants
Hello, thank you for all the wonderful work on Gleam! On v1.4.1 and the current main branch, but not on v1.2.1, running on Ubuntu and compiling to BEAM, I noticed the following small program will crash the compiler:

```gleam
pub type Bug {
  Ant
  Bee
  Bee
  Caterpillar
}

pub fn get_bugs(bug: Bug) {
  case bug {
    Ant -> "And"
    Bee -> "Bee"
    Caterpillar -> "Caterpillar"
  }
}
```
The error msg given by the compiler on v1.4.1 is:
```
Panic: compiler-core/src/exhaustiveness.rs:746
        Custom type variants must exist: Type { name: "Bug", hint: AlternativeTypes(["Bool", "Int", "List", "UtfCodepoint", "Result", "BitArray", "Nil", "String", "Bug", "Float"]) }
Gleam version: 1.4.1
Operating system: linux
```
The error msg given by the compiler on the current main branch is:
```
Panic: compiler-core/src/exhaustiveness.rs:539
        Case must exist
Gleam version: 1.4.1
Operating system: linux
```

On v1.2.1 and v1.4.1:
This code will compile and throw an error about the duplicate Caterpillar definition:
```gleam
pub type Bug {
  Ant
  Bee
  Caterpillar
  Caterpillar
}

pub fn get_bugs(bug: Bug) {
  "Bug!"
}
```
On v1.2.1 and v1.4.1 (but not the current main branch) this code will crash the compiler:
```gleam
pub type Bug {
  Ant
  Bee
  Caterpillar
  Caterpillar
}

pub fn get_bugs(bug: Bug) {
  case bug {
    Ant -> "And"
    Bee -> "Bee"
    Caterpillar -> "Caterpillar"
  }
}
```
on v1.4.1 it will give the following error:
```
Panic: compiler-core/src/exhaustiveness.rs:746
        Custom type variants must exist: Type { name: "Bug", hint: AlternativeTypes(["Bool", "Int", "List", "UtfCodepoint", "Result", "BitArray", "Nil", "String", "Bug", "Float"]) }
Gleam version: 1.4.1
Operating system: linux
```

So it seems that when the exhaustiveness check is run for the case statement in get_bugs, it will crash when there is _some_ set of duplicate variants. It seems like #3490 fixed a subset of the issue, but there is still a case where this pattern crashes the compiler.

Hope this helps! Let me know if any more info is needed.
