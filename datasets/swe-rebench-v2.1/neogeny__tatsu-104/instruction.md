@@keyword confusion
This here is valid:
```
@@namechars :: '_'
@@keyword :: if else not and or false true var let type
```

But if you swap those two lines:
```
@@keyword :: if else not and or false true var let type
@@namechars :: '_'
```

It gives the following error:
```
no available options :
@@namechars :: '_'
 ^
decorator
rule
grammar
start
```
