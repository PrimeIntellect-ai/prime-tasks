Nested lists are not rendered as nested
**Describe the bug**
Nested lists are not rendered as nested.

**The delta code which generates the Problem**

```
{"ops":[{"insert":"Level 1A"},{"attributes":{"list":"bullet"},"insert":"\n"},{"insert":"Level 2A"},{"attributes":{"indent":1,"list":"bullet"},"insert":"\n"},{"insert":"Level 2B"},{"attributes":{"indent":1,"list":"bullet"},"insert":"\n"},{"insert":"Level 1B"},{"attributes":{"list":"bullet"},"insert":"\n"}]}
```

**The expected html output the delta should produce**

```
<ul><li>Level 1A<ul><li>Level 2A</li><li>Level 2B</li></ul></li><li>Level 1B</li></ul>
```

**Expected behavior**
The expected behavior is to render nested lists

**Screenshots**
Editor: <img width="555" alt="Screen Shot 2022-10-31 at 3 18 45 PM" src="https://user-images.githubusercontent.com/4413670/199102581-cd2991e7-0085-4c46-b6ab-223ddf018d8f.png">

Rendered with nadar: <img width="282" alt="Screen Shot 2022-10-31 at 3 18 53 PM" src="https://user-images.githubusercontent.com/4413670/199102584-c3488a74-44d4-433a-bee9-5ba0fa778e92.png">


**Additional context**
DBlackborough sent me to this QuillJS render library because I needed support for nested lists and his didn't support it. I thought he was implying this library did support them.
