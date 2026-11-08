Add varargs to Group?
In addition to the slice of Nodes.

### Additional contract requirements

- Add a public type `Group` in package `gomponents` that is a slice of `Node`, so that a `Group` value can be built from a `[]Node` and from a composite literal of `Node` values, and can be used directly as a `Node` and as a `fmt.Stringer`.
- Add a public method `Group.String() string` that returns the concatenated HTML representation of the group's child nodes.
- Add a public method `Group.Render(w io.Writer) error` that renders the group's child nodes sequentially to the provided writer.
- Change the public function `Map[T any](ts []T, cb func(T) Node) Group` in package `gomponents` so that it maps each element of the input slice to a `Node` using the callback and returns the result as a `Group`.
