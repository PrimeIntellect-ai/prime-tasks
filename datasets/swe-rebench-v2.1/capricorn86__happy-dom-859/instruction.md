Add support for node.normalize()
https://developer.mozilla.org/en-US/docs/Web/API/Node/normalize

### Additional contract requirements

- Nodes expose a public method `normalize(): void`, declared on the `INode` interface in `packages/happy-dom/src/nodes/node/INode.ts`. It takes no arguments and returns no value.
- `NodeUtility` in `packages/happy-dom/src/nodes/node/NodeUtility.ts` exposes a public static method `isTextNode(node: INode | null): node is IText`. It returns `true` when the argument is a text node and `false` otherwise, including for `null` and for non-node values. Its return type is a type guard that narrows the argument to `IText`.
