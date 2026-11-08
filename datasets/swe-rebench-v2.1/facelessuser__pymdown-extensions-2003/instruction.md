[Feature request] Support nested snippets by excluding all scissor lines from rendering
### Description

When writing tutorials, a common use-case is to first show small parts of a file, before showing more extensive parts (or the entire file). For example:

```
// --8<-- [start:hello]
fun hello() {
	blah blah;

	// --8<-- [start:interesting]
	// Do some interesting stuff here!
	var x = foo();
	bar(x);
	// --8<-- [end:interesting]
}
// --8<-- [end:hello]
```

When `hello` is then included in some markdown, it will render a block like so:

```
fun hello() {
	blah blah;

	// --8<-- [start:interesting]
	// Do some interesting stuff here!
	var x = foo();
	bar(x);
	// --8<-- [end:interesting]
}
```

But the scissors aren't at all relevant to the example, and it's not desirable for the user to see them. It would be much nicer if they would see the following:

```
fun hello() {
	blah blah;

	// Do some interesting stuff here!
	var x = foo();
	bar(x);
}
```

One workaround is of course to *duplicate* the code (either in the same or different files, depending on how it works) such that there are no nested snippets, but that's a bit messy and makes it harder to maintain.

### Benefits

It would benefit anyone wanting to render snippets containing nested snippets.

### Solution Idea

If there are reasons for not wanting this behavior by default, perhaps it could be enabled as an option.

### Additional contract requirements

- Escaped snippet markers: when a section is included, a line inside that section whose snippet marker is preceded by one or more `;` characters is escaped and is not treated as a section boundary. Such a line is rendered as ordinary content with the first `;` removed (for example, `/* ;--8<-- [start: name] */` renders as `/* --8<-- [start: name] */`).
