Missing type checks
### Describe the bug
When translating a function where one of the arguments can have multiple types, only the type of the argument whose type can change is checked. This leads to segmentation faults if the wrong type is passed to the other arguments.

### To Reproduce
Provide code to reproduce the behaviour:
```python
@template('T', ['int', 'float'])
def test_types(unknown_type : 'T', known_type : int):
    print(unknown_type, known_type)
```

when called with:
```python
test_types(2.0, 3.0)
```

### Error details
Provide the generated code, or the error message:
```c
int64_t test_types_type_check(PyObject* unknown_type_obj, PyObject* known_type_obj)
{
    int64_t type_indicator;
    type_indicator = INT64_C(0);
    if (PyIs_NativeInt(unknown_type_obj))
    {
        type_indicator += INT64_C(0);
    }
    else if (PyIs_NativeFloat(unknown_type_obj))
    {
        type_indicator += INT64_C(1);
    }
    else
    {
        PyErr_SetString(PyExc_TypeError, "Unexpected type for argument unknown_type");
        return -INT64_C(1);
    }
    return type_indicator;
}

PyObject* test_types_wrapper(PyObject* self, PyObject* args, PyObject* kwargs)
{
    PyObject* unknown_type_obj;
    PyObject* known_type_obj;
    int64_t type_indicator;
    static char *kwlist[] = {
        "unknown_type",
        "known_type",
        NULL
    };
    if (!PyArg_ParseTupleAndKeywords(args, kwargs, "OO", kwlist, &unknown_type_obj, &known_type_obj))
    {
        return NULL;
    }
    type_indicator = test_types_type_check(unknown_type_obj, known_type_obj);
    if (type_indicator == INT64_C(0))
    {
        return test_types_0000_wrapper(unknown_type_obj, known_type_obj);
    }
    else if (type_indicator == INT64_C(1))
    {
        return test_types_0001_wrapper(unknown_type_obj, known_type_obj);
    }
    else
    {
        PyErr_SetString(PyExc_TypeError, "Unexpected type combination");
        return NULL;
    }
}
```

### Expected behaviour
The function `test_types_type_check` should also check the types of the other arguments and raise an error if they have the wrong type. There could be a special code for this to allow `test_types_type_check` to set the error string.

### Language
Fortran/C
