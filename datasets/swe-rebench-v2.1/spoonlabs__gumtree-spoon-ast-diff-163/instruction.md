API for returning children of `CtVirtualElement`
From `diffmin`'s point of view, it would be great if I can get children of `CtVirtualElement` - usually modifiers. They would be helpful while setting modifiers on a `CtType` using the `setModifiers` API. This API would be analogous to `CtWrapper`'s `getValue` API.

### Additional contract requirements

- Add a public `CtVirtualElement.getChildren()` method returning a `java.util.Collection<?>` of its children, including modifier nodes when present. The returned collection must be unmodifiable.
