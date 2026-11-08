Add wrapping of a FunctionDefArgument containing a class
### Describe the feature
I want to be able to call functions and pass class arguments.

### Test Code
Provide code which does not currently work but which should do when this issue is fixed:
```python
class Point:
    def __init__(self, x : int):
         self._x = x

def get_point(x : int):
    return Point(x)

def print_point(p : Point):
    print(p.x)
```

### Proposed Solution
[HIDDEN] The resulting code should look something like:
```c
[HIDDEN]

static PyTypeObject PyPointType = {
    PyVarObject_HEAD_INIT(NULL, 0)
    .tp_name = "mod.Point",
    .tp_doc = PyDoc_STR("<class_docstring>"),
    .tp_basicsize = sizeof(PyPointObject),
    .tp_itemsize = 0,
    .tp_flags = Py_TPFLAGS_DEFAULT,
    .tp_new = PyType_GenericNew,
};

PyObject* print_point_wrapper(PyObject* self, PyObject* args, PyObject* kwargs)
{
    PyObject* p_obj;
    Point* p;
    static char *kwlist[] = {
        "p",
        NULL
    };
    if (!PyArg_ParseTupleAndKeywords(args, kwargs, "O", kwlist, &p_obj))
    {
        return NULL;
    }
    [HIDDEN]
    print_point(p);
    return Py_None;
}
```

### Issues which must be tackled first
- #1493 : To have a class instance
- #1494 : To get access to a class instance in a Module for testing
- #1444 : Functions which take classes as arguments

### Additional contract requirements

Expose the following public functions:

- `get_x_from_B(b_obj: B)`: takes a required, non-null instance of class `B` and returns the value of its `x` attribute. A call that omits the argument, passes `None`, or passes an object that is not a `B` instance must fail with an error instead of being treated as a valid `B` instance.
- `get_an_x_from_B(b_obj: B = None)`: returns the value of `b_obj.x` when a `B` instance is supplied, and `-2.0` when the argument is omitted or explicitly `None`. A supplied argument that is neither `None` nor a `B` instance must fail with an error.
