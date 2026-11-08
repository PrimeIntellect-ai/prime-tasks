Enum variants don't merge even if they were the same
**Describe the bug**
Enum variants don't merge even if they were the same.

**To Reproduce**
```
nickel> `A & `A
error: Non mergeable terms
  ┌─ repl-input-1:1:1
  │
1 │ `A & `A
  │ ^^---^^
  │ │    │
  │ │    with this expression
  │ merged here
  │ cannot merge this expression
```

**Expected behavior**
It should result in
```
`A
```

**Environment**
 - OS name + version: `Linux xps 5.10.89-1-MANJARO #1 SMP PREEMPT Wed Dec 29 18:09:17 UTC 2021 x86_64 GNU/Linux`
 - Version of the code: a48713d

**Additional context**
I came across the issue when I applied the same contract (which specifies default enum variant) twice, something like
```
let T = {a | <A, B> | default = `A } & {a = `A} in {} | #T | #T
```
