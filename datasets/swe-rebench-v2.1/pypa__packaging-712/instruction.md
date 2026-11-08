different result of  '_compare_equal' prefix match with epoch
see the results:

![图片](https://user-images.githubusercontent.com/11829223/227157371-1d2cd8f1-a987-498e-a451-b1b04ffd5ebc.png)

this happens when specifier is longer that prospective and epoch is involved. The problem originates from the function `_pad_version` in `packaging.specifiers`.

```python
def _pad_version(left: List[str], right: List[str]) -> Tuple[List[str], List[str]]:
    left_split, right_split = [], []

    [HIDDEN]

    # Insert our padding
    left_split.insert(1, ["0"] * max(0, len(right_split[0]) - len(left_split[0])))
    right_split.insert(1, ["0"] * max(0, len(left_split[0]) - len(right_split[0])))

    return (list(itertools.chain(*left_split)), list(itertools.chain(*right_split)))

```
This function didn't take into account the situation where epoch exists. see the testing results.

![图片](https://user-images.githubusercontent.com/11829223/227159865-0b7d2d77-3e81-44ca-bc81-f110f4f903c0.png)

### Additional contract requirements

- For `==` prefix matching, treat an omitted epoch as epoch 0, and match only when the candidate version and prefix have the same epoch. For example, `2!1.0` does not match `==1.0.0.*`, and `1.0` does not match `==2!1.0.0.*`.
- When the prefix has more release components than the candidate version, treat missing candidate release components as zero. For example, `2!1.0.0` matches `==2!1.0.0.0.*`.
