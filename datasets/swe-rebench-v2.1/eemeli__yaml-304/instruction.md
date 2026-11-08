Cloning a Document
What is the recommended way to clone a document ?
I need to create some instances from a common skeleton.
I currently do it like this, but it is probably not optimal.

```javascript
const instance1 = YAML.parseDocument(skel.toString())
const instance2 = YAML.parseDocument(skel.toString())
```

Thank you !

### Additional contract requirements

- Provide a `Document.clone()` method, called as `doc.clone()`, that returns a new document cloned from the receiver.
