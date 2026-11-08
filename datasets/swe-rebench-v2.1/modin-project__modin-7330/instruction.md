BUG: columns mismatch after df.update
### Modin version checks

- [X] I have checked that this issue has not already been reported.

- [X] I have confirmed this bug exists on the latest released version of Modin.

- [X] I have confirmed this bug exists on the main branch of Modin. (In order to do this you can follow [this guide](https://modin.readthedocs.io/en/stable/getting_started/installation.html#installing-from-the-github-main-branch).)


### Reproducible Example

```python
import modin.pandas as pd

df = pd.DataFrame({'C': [1, 2, 3], 'B': [400, 500, 600]})
new_df = pd.DataFrame({'B': [4, 5, 6], 'A': [7, 8, 9]})
df.update(new_df)
print(df)
   B  C
0  4  1
1  5  2
2  6  3
```


### Issue Description

Columns get ordered while in pandas not.

### Expected Behavior

Should match pandas.

### Error Logs

<details>

```python-traceback

Replace this line with the error backtrace (if applicable).

```

</details>


### Installed Versions

<details>

Replace this line with the output of pd.show_versions()

</details>
