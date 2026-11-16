Super type node does not need to be nested
Consider the following piece of code and its tree string.

```java
class Main extends SuperClass1 { }
```
```
-1@@
	65190232@@Main
		-1421180655@@
			-1203492450@@SuperClass1
```

I am not sure what is the need for nesting `SuperClass1` below a node without a label as Java allows a class to extend from _exactly 1 super class_. I propose that we remove the nesting and make `SuperClass1` a direct child of `Main`. The proposed tree would look something like this:

```
-1@@
	65190232@@Main
		-1203492450@@SuperClass1
```

> Test case is taken from [here](https://github.com/SpoonLabs/gumtree-spoon-ast-diff/blob/master/src/test/java/gumtree/spoon/AstComparatorTest.java#L1763).
