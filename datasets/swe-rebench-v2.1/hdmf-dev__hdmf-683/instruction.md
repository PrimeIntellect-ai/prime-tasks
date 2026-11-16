Adding child to parent container does not always mark parent as modified
## Description

If a child container already has a parent and that child is added to a new container (so a link will be made in the ObjectMapper), then currently, the new container is not marked as modified. This is relevant when exporting. Adding a link to an existing object would not mark the file as modified, so it would not get rebuilt.

## Steps to Reproduce

```python
child_obj1 = Container('test child 1')
obj1 = ContainerWithChild()
obj1.set_modified(False)  # set to False so that we can test that it is set to True next
obj1.field1 = child_obj1
self.assertTrue(obj1.modified)
self.assertIs(obj1.field1, child_obj1)

obj3 = ContainerWithChild()
obj3.set_modified(False)  # set to False so that we can test that it is set to True next
obj3.field1 = child_obj1  # child_obj1 already has a parent
self.assertTrue(obj3.modified)
self.assertIs(obj3.field1, child_obj1)
```
```python
obj1 = Container('obj1')
obj2 = Container('obj2')
obj1.parent = obj2
foo = Foo()   # Foo is a MultiContainerInterface
foo.set_modified(False)  # set to False so that we can test whether add_container makes it True
foo.add_container(obj1)
self.assertTrue(foo.modified)  # fails


```
## Environment

<!--Please describe your environment according to the following bullet points.-->

    Python Executable: Conda
    Python Version: Python 3.9
    Operating System: Windows
    HDMF Version: dev

## Checklist

- [x] Have you ensured the bug was not already [reported](https://github.com/hdmf-dev/hdmf/issues) ?
- [x] Have you included a brief and descriptive title?
- [x] Have you included a clear description of the problem you are trying to solve?
- [x] Have you included a minimal code snippet that reproduces the issue you are encountering?
- [x] Have you checked our [Contributing](https://github.com/hdmf-dev/hdmf/blob/dev/docs/CONTRIBUTING.rst) document?
