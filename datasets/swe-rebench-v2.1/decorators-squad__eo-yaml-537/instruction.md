Ghost Comments
Version: 6.0.1
Issue: Is a scalar node has both a comment and an inline comment, the next node will appear to have that same comment, even though it has no comments at all. For example if node B has an inline comment and the comment "hello world" above it and node C has no comments, then node C will also have the comment "hello world" even though it is not supposed to!

Given the following YML file

```
a: a
#hello world
b: b #inline
c: c
```

Read Using

```
YamlMapping mapping = ...
YamlNode Bnode = mapping.value("b");
System.out.println("B Node:" + Bnode.comment().value());
YamlNode Cnode = mapping.value("c");
System.out.println("C Node: " + Cnode.comment().value());
```

Will output

```
B Node:hello world
inline
C Node: hello world
```

This output is obviously incorrect because the C node does not have any comments. The correct output should be as follows.

```
B Node: hello world
inline
C Node:
```
