[BUG] `DropLabel` when  combined with other selectors does not exclude labels
```py
url='https://gist.githubusercontent.com/slopp/ce3b90b9168f2f921784de84fa445651/raw/4ecf3041f0ed4913e7c230758733948bc561f434/penguins.csv'
penguins = pd.read_csv(url).iloc[:, 1:]

In [15]: penguins.select(columns=[pd.api.types.is_numeric_dtype, jn.DropLabel('year')]).columns
Out[15]:
Index(['bill_length_mm', 'bill_depth_mm', 'flipper_length_mm', 'body_mass_g',
       'year', 'species', 'island', 'bill_length_mm', 'bill_depth_mm',
       'flipper_length_mm', 'body_mass_g', 'sex'],
      dtype='object')

In [16]: penguins.columns
Out[16]:
Index(['species', 'island', 'bill_length_mm', 'bill_depth_mm',
       'flipper_length_mm', 'body_mass_g', 'sex', 'year'],
      dtype='object')
```

`year` should be excluded from the selection
