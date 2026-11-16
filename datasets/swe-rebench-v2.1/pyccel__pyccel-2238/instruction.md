Variables are used uninitialized in C
### Describe the bug
variables that are declared inside an if block are declared outside it in C and if one variable, i e  an array, depends on another variable, i e an integer, for initialization, then it will be declared erroneously.

### To Reproduce
```python
import numpy as np

class A:
    def __init__(self, x : 'int'):
        self.x = x
        self.T = np.array([1,4,6])
    @property
    def f(self):
        if self.x == 0:
            y = np.zeros(self.x)
            return y
        else:
            p = self.x
            s = 1
            n = 1
            y = np.array([np.sum(self.T[i:i+p])/p for i in range(s, s+n)])
            return y
```

### Error details
```c
array_double_1d A__f(struct A* self)
{
    int64_t p;
    int64_t s;
    int64_t n;
    int64_t i;
    int64_t Dummy_0000;
    double* y_ptr;
    double* y_ptr_0001;
    int64_t Dummy_0002;
    int64_t Dummy_0003_ptr[i + p - i];
    array_int64_1d Dummy_0003 = cspan_md_layout(c_ROWMAJOR, Dummy_0003_ptr, i + p - i);
    array_double_1d y = {0};
    if (self->x == INT64_C(0))
    {
        y_ptr = malloc(sizeof(double) * (self->x));
        y = (array_double_1d)cspan_md_layout(c_ROWMAJOR, y_ptr, self->x);
        c_foreach(Dummy_0001, array_double_1d, y) {
            *(Dummy_0001.ref) = 0.0;
        }
        return y;
    }
    else
    {
        p = self->x;
        s = INT64_C(1);
        n = INT64_C(1);
        y_ptr_0001 = malloc(sizeof(double) * (n));
        y = (array_double_1d)cspan_md_layout(c_ROWMAJOR, y_ptr_0001, n);
        Dummy_0000 = INT64_C(0);
        for (i = s; i < s + n; i += INT64_C(1))
        {
            Dummy_0002 = INT64_C(0);
            c_foreach(Dummy_0004, array_int64_1d, Dummy_0003) {
                Dummy_0002 = Dummy_0002 + (*Dummy_0004.ref);
            }
            (*cspan_at(&y, Dummy_0000)) = (double)(Dummy_0002) / (double)(p);
            Dummy_0000 = Dummy_0000 + INT64_C(1);
        }
        return y;
    }
}
```

### Expected behavior
dependent declarations should be conducted in order.

### Language
C
