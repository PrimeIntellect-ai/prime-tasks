Function call in if condition printed in wrong location
Regarding your interesting example:
```python
def f(k : int):
    a = {1:1.0, 2:2.0}
    b = {1:True, 2: False}
    if b.pop(k):
        return a.pop(k)
    else:
        return 3.0
```
It generates the following C function:
```c
double f(int64_t k)
{
    hmap_int64_t_double a = {0};
    hmap_int64_t_bool b = {0};
    double Dummy_0000;
    bool Dummy_0001;
    double Out_0001;
    a = c_init(hmap_int64_t_double, {{INT64_C(1), 5.0}, {INT64_C(2), 6.0}});
    b = c_init(hmap_int64_t_bool, {{INT64_C(1), 1}, {INT64_C(2), 0}});
    if (Dummy_0001)
    {
        Dummy_0000 = hmap_int64_t_double_pop(&a, k);
        Out_0001 = Dummy_0000;
        hmap_int64_t_double_drop(&a);
        hmap_int64_t_bool_drop(&b);
        return Out_0001;
    }
    else
    {
        Dummy_0001 = hmap_int64_t_bool_pop(&b, k); // <-- PROBLEM
        hmap_int64_t_double_drop(&a);
        hmap_int64_t_bool_drop(&b);
        return 3.0;
    }
    hmap_int64_t_double_drop(&a);
    hmap_int64_t_bool_drop(&b);
}
```
Beside the 'header guard' issue that I fixed, I think there is another issue here - `hmap_int64_t_bool_pop(&b, k)` is evaluated inside the `else` block instead of being computed before the conditional statement. This results in incorrect behavior, as the conditional logic depends on the value of `b.pop(k)` but evaluates it at the wrong point.

This issue is not specific to the `dict.pop` case. It also occurs in other cases, such as:
```python
def test_min():
    if min(5,6):
        return 1
    else:
        return 0
```
Which generates the following C code:
```c
int64_t test_min(void)
{
    int64_t Dummy_0000;
    int64_t Dummy_0001;
    if (((Dummy_0000 < Dummy_0001 ? Dummy_0000 : Dummy_0001) != 0))
    {
        return INT64_C(1);
    }
    else
    {
        Dummy_0000 = INT64_C(5); // <-- PROBLEM
        Dummy_0001 = INT64_C(6);
        return INT64_C(0);
    }
}
```
Here, the variables `Dummy_0000` and `Dummy_0001` used in the `min` function are only evaluated in the `else` block, leading to incorrect behavior because the condition depends on their values.
It seems that this issue occurs specifically within `if-else` blocks, as `if` blocks alone appear to function correctly.
Since its not specific to `dict.pop`, resolving it may fall outside the scope of this PR, but it should certainly be addressed in future work. Let me know what you think :smile:

_Originally posted by @emmanuel-ferdman in https://github.com/pyccel/pyccel/issues/2143#issuecomment-2587577755_

### Additional contract requirements

- When a side-effecting call is used as an `if`/`else` condition, evaluate it before using its result to select a branch; do not defer the call into either branch.
- When a `min` expression in an `if`/`else` condition requires temporary values, compute those values before selecting a branch.
