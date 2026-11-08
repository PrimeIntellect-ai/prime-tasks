Reference being missed for symbol used in "cons" syntax
**Describe the bug**
When renaming a symbol that is being being used to create a list with cons syntax, or trying to find a reference for a symbol that is being used to create with cons syntax, the reference is missed.

```scala
val my@@Number = 3
val myList = List(1, 2, 3)

myNumber :: myList

myNumber :: 5 :: Nil
```
If I try to trigger either a rename or a find references at the `@@` position, it will neither find nor rename the other two occurrences of `myNumber`.

**To Reproduce**
Steps to reproduce the behavior:
1. Paste the above code in a scala file
2. Trigger a rename where the `@@` would be or a find references
3. See that the other two references aren't caught

**Expected behavior**
I would expect the rename to rename the other two occurrences, and I'd expect a find references to also show the two references.

**Installation:**
- Operating system: macOS
- Editor: Vim
- Metals version: `0.9.3+63-1c4ba22a-SNAPSHOT`

**Additional context**
I did check to see if there were correctly captured in scalameata, and it doesn't look like they are. ~look like they are, which points towards us missing something on the metals side.~

```
❯ metap .
src/main/scala/Main.scala
-------------------------

Summary:
Schema => SemanticDB v4
Uri => src/main/scala/Main.scala
Text => empty
Language => Scala
Symbols => 5 entries
Occurrences => 13 entries
Synthetics => 4 entries

Symbols:
_empty_/Main. => final object Main extends AnyRef with App { +2 decls }
_empty_/Main.myList. => val method myList: List[Int]
_empty_/Main.myNumber. => val method myNumber: Int
local0 => final val local rassoc$1: Int
local1 => final val local rassoc$3: Int

Occurrences:
[0:7..0:11) <= _empty_/Main.
[0:20..0:23) => scala/App#
[0:24..0:24) => java/lang/Object#`<init>`().
[2:6..2:14) <= _empty_/Main.myNumber.
[3:6..3:12) <= _empty_/Main.myList.
[3:15..3:19) => scala/collection/immutable/List.
[5:2..5:10) => local0
[5:11..5:13) => scala/collection/immutable/List#`::`().
[5:14..5:20) => _empty_/Main.myList.
[7:2..7:10) => local1
[7:11..7:13) => scala/collection/immutable/List#`::`().
[7:16..7:18) => scala/collection/immutable/List#`::`().
[7:19..7:22) => scala/collection/immutable/Nil.

Synthetics:
[3:15..3:19) => *.apply[Int]
[5:11..5:20) => *[Int]
[7:11..7:22) => *[Int]
[7:16..7:22) => *[Int]
```

**Search terms**
rename, find references
