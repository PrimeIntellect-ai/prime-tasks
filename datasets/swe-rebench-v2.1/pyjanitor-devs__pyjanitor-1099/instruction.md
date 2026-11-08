duplicated columns generate more rows than required in `pivot_longer`
# Brief Description

If the columns are duplicated, more rows are generated than necessary (duplicated) when melted.

# System Information

<!-- System information helps us. To keep things simple, just let us know the OS and Python version first.
You can provide the optional information later. -->

- Operating system: macOS
- Python version (required): 3.8

# Minimally Reproducible Code

copied from [SO](https://stackoverflow.com/q/72126060/7175713)
```
rows = [['credit', 1, 1, 2, 3]]
columns = ['Type', 'amount', 'active', 'amount', 'active']

df = pd.DataFrame(rows, columns=columns)
df = df.set_index('Type')


        amount  active  amount  active
Type
credit       1       1       2       3


# output from pivot_longer
df.pivot_longer(names_to = ['amount', 'active'], names_pattern = ['amount', 'active'])

   amount  active
0       1       1
1       2       3
2       1       1
3       2       3

# expected output

        amount  active
Type
credit       1       1
credit       2       3
```
