runtime inferred Negative numpy array slices do not translate well in C
### Describe the bug
When computing slices of numpy arrays with variable slices, translation is performed without negativity check.

### To Reproduce
```python
import numpy as np
from pyccel.decorators import allow_negative_index

@allow_negative_index('a')
def f(x : 'int'):
    a = np.array([1,2,3,4,5])
    b = a[-2 * x:-x]
    print(a[-x])
    print(b)

if __name__ == '__main__':
    f(1)
```

### Error details
```c
void f(int64_t x)
{
    array_int64_1d a = {0};
    array_int64_1d b = {0};
    int64_t* a_ptr;
    int64_t i;
    a_ptr = malloc(sizeof(int64_t) * (INT64_C(5)));
    a = (array_int64_1d)cspan_md_layout(c_ROWMAJOR, a_ptr, INT64_C(5));
    (*cspan_at(&a, INT64_C(0))) = INT64_C(1);
    (*cspan_at(&a, INT64_C(1))) = INT64_C(2);
    (*cspan_at(&a, INT64_C(2))) = INT64_C(3);
    (*cspan_at(&a, INT64_C(3))) = INT64_C(4);
    (*cspan_at(&a, INT64_C(4))) = INT64_C(5);
    b = cspan_slice(array_int64_1d, &a, {(-INT64_C(2)) * x < INT64_C(0) ? a.shape[INT64_C(0)] - (-INT64_C(2)) * x : (-INT64_C(2)) * x, -x < INT64_C(0) ? a.shape[INT64_C(0)] + x : -x});
    printf("%"PRId64"\n", (*cspan_at(&a, -x < INT64_C(0) ? INT64_C(5) - x : -x)));
    printf("[");
    for (i = INT64_C(0); i < b.shape[INT64_C(0)] - INT64_C(1); i += INT64_C(1))
    {
        printf("%"PRId64" ", (*cspan_at(&b, i)));
    }
    printf("%"PRId64"]\n", (*cspan_at(&b, b.shape[INT64_C(0)] - INT64_C(1))));
    free(a.data);
    a.data = NULL;
}
```
```bash
boo: pyccel/__pyccel__/STC/src/../include/stc/cspan.h:400: _cspan_slice: Assertion `(oshape[oi] > 0) & !((size_t)(shape[i]) < (size_t)(end))' failed.
[1]    16097 IOT instruction (core dumped)  ./boo
```
### Expected behavior
The _cspan_slice assertion should not fail.

### Language
C

### Additional context
Add any other context about the problem here.
