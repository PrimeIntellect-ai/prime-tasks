Global Struct Initialisation Parsed Incomplete
Hello,

I think that I discovered a bug in parsing global initialised structs. Please use the following code as an example:

```
struct filesystem {
	void (*open)(int a);
};

void my_open(int a) {
	int b;
	b = a;
	return;
}

static const struct filesystem my_fs = {
	.open = &my_open,
};

int main(int argc, char *argv[]) {
	static int i;
	static const struct filesystem my_other_fs = {
		 .open = &my_open,
	};
	struct filesystem real_fs;
	real_fs.open = &my_open;
	i = 0;
}
```


The call for the initialisation of `my_other_fs` is parsed correctly:

```
joern> cpg.method("main").local.name("my_other_fs").referencingIdentifiers.astParent.isCall.argument(2).astChildren.astChildren.code.l
res13: List[String] = List(".open = &my_open")

```

However, that's not the case for the global struct `my_fs`, e.g., no Identifier node is created:

```
joern> cpg.local("my_fs").l
res15: List[Local] = List(
  Local(
    id -> 3074457345618260637L,
    closureBindingId -> None,
    code -> "my_fs",
    columnNumber -> None,
    dynamicTypeHintFullName -> ArraySeq(),
    lineNumber -> None,
    name -> "my_fs",
    order -> 4,
    typeFullName -> "static const filesystem"
  )
)

joern> cpg.local("my_fs").referencingIdentifiers.l
res16: List[Identifier] = List()

joern> cpg.identifier("my_fs").l
res17: List[Identifier] = List()
```

Maybe related to #405

### Additional contract requirements

- The global struct initializer for `my_fs` must preserve its designated member
  initializer `.open = &my_open` in the AST, exactly as the local `my_other_fs`
  initializer does. Concretely, the query
  `cpg.local.name("my_fs").referencingIdentifiers.astParent.isCall.argument(2).astChildren.astChildren.code.l`
  must return `List(".open = &my_open")`.
