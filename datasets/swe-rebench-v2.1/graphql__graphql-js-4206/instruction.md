Test all functions (with AST input) that they handle `undefined` instead of array properites
Based on @mjmahone comment https://github.com/graphql/graphql-js/pull/2084#discussion_r313964490
> I know we ran into problems in the past when hand-modeling the AST where, unless you explicitly set directives: [], you'd end up getting an undefined reference, even though the flow type allowed it.

Currently `parse` always return empty arrays (and never `undefined`) but AST definitions explicitly support `undefined`.

This is done to make AST forward-compatible meaning old code that generate/transformate AST and doesn't know about new properties (e.g. `interfaces` on `InterfaceTypeDefinitionNode` node) is still compatible with newer versions of `graphql-js`.

It also means it's very easy to manually create nodes, for example creating `FieldNode` you can safely omit `arguments`, `directives` and `selectionSet` properties so minimal field will look like:
```js
{
  kind: 'Field',
  name: { kind: 'Name', value: 'foo' },
}
```

At the same time we need to be sure that functions like `buildSchema`, `extendSchema`, `print`, `execute`, etc. are actually ready to handle such functions and don't crash when they get `undefined` instead of an empty array.

### Additional contract requirements

- When parsing, absent optional list properties in produced AST nodes must be `undefined`, not empty arrays. The property must be present on the produced node with the value `undefined` (an own property: `'variableDefinitions' in node` is `true` and `node.variableDefinitions === undefined`), rather than being omitted from the node object.
- When `validateSchema()` validates a schema whose `BadUnion` has a `String` member and whose AST node has `types` set to `undefined`, it must report the exact message `Union type BadUnion can only include Object types, it cannot include String.` When `BadObject` implements `SomeInputObject` and its AST node has `interfaces` set to `undefined`, it must report the exact message `Type BadObject must only implement Interface types, it cannot implement SomeInputObject.`
