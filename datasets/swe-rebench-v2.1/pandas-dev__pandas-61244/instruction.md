BUG: scatter and line matplotlib plots not compatible for sharex=True datetime plots
### Pandas version checks

- [x] I have checked that this issue has not already been reported.

- [x] I have confirmed this bug exists on the [latest version](https://pandas.pydata.org/docs/whatsnew/index.html) of pandas.

- [x] I have confirmed this bug exists on the [main branch](https://pandas.pydata.org/docs/dev/getting_started/install.html#installing-the-development-version-of-pandas) of pandas.


### Reproducible Example

```python
datetime_list = [datetime.datetime(year = 2025, month = 1, day = 1, hour = n) for n in range(23)]
y = [n for n in range(23)]

df = pd.DataFrame(columns = ['datetime','y'])
for i, n in enumerate(datetime_list):
    df.loc[len(df)] = [n,y[i]]

#Plotting with pandas - first subplot shows up as blank
fig, ax = plt.subplots(2, sharex=True)
df.plot.scatter(x = 'datetime', y = 'y', ax = ax[0])
df.plot(x = 'datetime', y = 'y', ax = ax[1])

#Plotting with matplotlib - this works
fig, ax = plt.subplots(2, sharex=True)
ax[0].scatter(df['datetime'],df['y'])
ax[1].plot(df['datetime'],df['y'])
```

### Issue Description

When I am trying to plot a line plot and scatter plot using df.plot and df.plot.scatter, the scatter plot shows up as blank when I select sharex=True when making the figure and axes.

```python
#Plotting with pandas - first subplot shows up as blank
fig, ax = plt.subplots(2, sharex=True)
df.plot.scatter(x = 'datetime', y = 'y', ax = ax[0])
df.plot(x = 'datetime', y = 'y', ax = ax[1])
```

![Image](https://github.com/user-attachments/assets/df1b5ee5-dcec-44dd-911e-bcfcee2500db)

However, if I plot using the standard matplotlib way of plotting (ax.scatter and ax.plot), both subplots show up correctly when I set sharex=True for the figure.

```python
#Plotting with matplotlib - this works
fig, ax = plt.subplots(2, sharex=True)
ax[0].scatter(df['datetime'],df['y'])
ax[1].plot(df['datetime'],df['y'])
```

![Image](https://github.com/user-attachments/assets/fb9a7ae4-2c51-4058-9a30-52919958cdbc)

### Expected Behavior

I would expect for the both subplots to show up, not blank. The behavior should be more similar to the traditional way of plotting with matplotlib.

### Installed Versions

<details>


INSTALLED VERSIONS
------------------
commit                : 0691c5cf90477d3503834d983f69350f250a6ff7
python                : 3.13.1
python-bits           : 64
OS                    : Windows
OS-release            : 10
Version               : 10.0.19045
machine               : AMD64
processor             : Intel64 Family 6 Model 158 Stepping 9, GenuineIntel
byteorder             : little
LC_ALL                : None
LANG                  : None
LOCALE                : English_United States.1252

pandas                : 2.2.3
numpy                 : 2.2.2
pytz                  : 2025.1
dateutil              : 2.9.0.post0
pip                   : 24.3.1
Cython                : None
sphinx                : None
IPython               : 8.32.0
adbc-driver-postgresql: None
adbc-driver-sqlite    : None
bs4                   : 4.13.3
blosc                 : None
bottleneck            : None
dataframe-api-compat  : None
fastparquet           : None
fsspec                : None
html5lib              : None
hypothesis            : None
gcsfs                 : None
jinja2                : 3.1.5
lxml.etree            : None
matplotlib            : 3.10.0
numba                 : None
numexpr               : None
odfpy                 : None
openpyxl              : 3.1.5
pandas_gbq            : None
psycopg2              : None
pymysql               : None
pyarrow               : None
pyreadstat            : None
pytest                : None
python-calamine       : None
pyxlsb                : None
s3fs                  : None
scipy                 : 1.15.1
sqlalchemy            : None
tables                : None
tabulate              : None
xarray                : None
xlrd                  : None
xlsxwriter            : None
zstandard             : None
tzdata                : 2025.1
qtpy                  : None
pyqt5                 : None

</details>
