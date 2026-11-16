StackOverflowError when the bound generic type binds to itself
**Describe the bug**
When when a generic type binds to itself, a `StackOverflowError` is thrown. Below is an example reproducer.

**To Reproduce**
Types:
```java
public interface TreeTypeContainer<T extends TreeTypeContainer<T>> {

    List<T> getChildren();

    void setChildren(List<T> children);
}

```

```java
public static class TreeContainer<T extends TreeTypeContainer<T>> {

    private TreeTypeContainer<T> tree;

    public TreeTypeContainer<T> getTree() {
        return tree;
    }

    public void setTree(TreeTypeContainer<T> tree) {
        this.tree = tree;
    }

}
```

```java
public static class ExampleTree implements TreeTypeContainer<ExampleTree> {

    private List<ExampleTree> children = new ArrayList<>();

    public List<ExampleTree> getChildren() {
        return children;
    }

    public void setChildren(List<ExampleTree> children) {
        this.children = children;
    }

}
```

Example test code:

```java
public static void main(final String... args) throws Throwable {
    try (Jsonb jsonb = JsonbBuilder.newBuilder().build()) {
        final TreeContainer<ExampleTree> tc = new TreeContainer<>();
        tc.setTree(new ExampleTree());

        // Throws a StackOverflowError
        System.out.println(jsonb.toJson(tc));
    }

}
```

**Expected behavior**
The type should be serialized.

**System information:**
 - OS: Linux
 - Java Version: 11
 - Yasson Version: 3.0.x

### Additional contract requirements

- For a `TreeContainer<TreeElement>` whose tree is a `TreeElement` named `parent` with one child named `child`, serialization must return exactly `{"tree":{"children":[{"children":[],"name":"child"}],"name":"parent"}}`.
