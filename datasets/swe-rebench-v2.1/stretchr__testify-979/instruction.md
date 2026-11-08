assert.ObjectsAreEqual work not correct with serialized\deserialized time.Time
**time.Time** not equals before and after serialization/deserialization to JSON on machine in **UTC**
reason: https://github.com/golang/go/issues/19486#issuecomment-292610767

code: https://play.golang.org/p/H0ACWIBZE3O

solution: change the **time.Time** comparison format. For example, [HIDDEN]

### Additional contract requirements

- `assert.ObjectsAreEqual` returns true for `time.Time` values representing the same instant when one has been serialized to JSON and deserialized.
- `assert.ObjectsAreEqual` returns false for `time.Time` values representing distinct instants.
