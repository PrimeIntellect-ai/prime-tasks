BUG: Invalid Stata file is generated if byteorder='big' is specified and strings are saved as strL type
### Pandas version checks

- [X] I have checked that this issue has not already been reported.

- [X] I have confirmed this bug exists on the [latest version](https://pandas.pydata.org/docs/whatsnew/index.html) of pandas.

- [X] I have confirmed this bug exists on the [main branch](https://pandas.pydata.org/docs/dev/getting_started/install.html#installing-the-development-version-of-pandas) of pandas.


### Reproducible Example

```python
import pandas as pd
df = pd.DataFrame(data={'strings': ["abc", "def", "ghi"]})
df.to_stata("test.dta", byteorder="big", version=117, convert_strl=["strings"]) # <-- invalid file created
```


### Issue Description

Although there is a documented argument defined to set it, [HIDDEN]

This results in the strL data always being saved in the default byteorder, even if the rest of the file isn't, resulting in following error when attempting to open the saved file, both in Pandas:
```python
>>> import pandas as pd
>>> df = pd.DataFrame(data={'strings': ["abc", "def", "ghi"]})
>>> df
  strings
0     abc
1     def
2     ghi
>>> df.to_stata("test.dta", byteorder="big", version=117, convert_strl=["strings"])
>>> df2 = pd.read_stata("test.dta")
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "pandas\io\stata.py", line 2082, in read_stata
    return reader.read()
  File "pandas\io\stata.py", line 1741, in read
    data = self._insert_strls(data)
  File "pandas\io\stata.py", line 1838, in _insert_strls
    data.isetitem(i, [self.GSO[str(k)] for k in data.iloc[:, i]])
  File "pandas\io\stata.py", line 1838, in <listcomp>
    data.isetitem(i, [self.GSO[str(k)] for k in data.iloc[:, i]])
KeyError: '4294967298'
```
or within Stata:
```
. use "test.dta"
.dta file corrupt
    The strL component of the file is corrupt.  Either the file was incorrectly constructed or it became
    corrupted since it was written.  In case the file was incorrectly constructed,the technical description of
    the problem is that there was an attempt to crosslink a strl to another strl that had not yet been defined.
r(688);

. dtaverify "test.dta"
  (file "test.dta" is .dta-format 117 from Stata 13)

 1. reading and verifying header
    release is 117
    byteorder MSF
    K (# of vars) is 2
    N (# of obs) is 3
    label length 0 ||
    date length 17 |10 Jun 2024 16:05|

 2. reading and verifying map
    map[ 1] =                    0
    map[ 2] =                  153
    map[ 3] =                  276
    map[ 4] =                  313
    map[ 5] =                  400
    map[ 6] =                  427
    map[ 7] =                  544
    map[ 8] =                  649
    map[ 9] =                  846
    map[10] =                  881
    map[11] =                  930
    map[12] =                 1005
    map[13] =                 1034
    map[14] =                 1046
    verifying map
    1 2 3 4 5 6 7 8 9 10 11 12 13 14

 3. reading and verifying vartypes

 4. reading and verifying varnames
    verifying varnames unique

 5. reading and verifying sort order
    verifying contents

 6. reading and verifying display formats
    verifying formats
    verifying formats correspond to variable type

 7. reading and verifying value-label assignment
    verifying value-label construction
    verifying value label and corresponding variable types

 8. reading and verifying variable-label assignment
    verifying variable labels construction

 9. reading and verifying characteristics
    (0 characteristics in file)

10. reading and verifying data
    (dtaverify_117 cannot verify that values are correct)
    verifying construction
    (1 strL variables)
    verifying strL construction
SERIOUS ERROR: (var,obs)=(2,1) has (v,o)=(1,2); v not strL
               chkijvo():  3301  subscript invalid
      strl_process_obs():     -  function returned error
     read_data_u_strls():     -  function returned error
           read_data_u():     -  function returned error
             read_data():     -  function returned error
              readfile():     -  function returned error
       verify_dta_file():     -  function returned error
                 <istmt>:     -  function returned error
r(3301);
```

### Expected Behavior

I would expect the saved file to open correctly in both Pandas:
```python
>>> import pandas as pd
>>> df = pd.DataFrame(data={'strings': ["abc", "def", "ghi"]})
>>> df
  strings
0     abc
1     def
2     ghi
>>> df.to_stata("test.dta", byteorder="big", version=117, convert_strl=["strings"])
>>> df2 = pd.read_stata("test.dta")
>>> df2
   index strings
0      0     abc
1      1     def
2      2     ghi
```

and Stata:
```
. use "test.dta"

. list

     +-----------------+
     | index   strings |
     |-----------------|
  1. |     0       abc |
  2. |     1       def |
  3. |     2       ghi |
     +-----------------+

. dtaverify "test.dta"
  (file "test.dta" is .dta-format 117 from Stata 13)

 1. reading and verifying header
    release is 117
    byteorder MSF
    K (# of vars) is 2
    N (# of obs) is 3
    label length 0 ||
    date length 17 |10 Jun 2024 16:12|

 2. reading and verifying map
    map[ 1] =                    0
    map[ 2] =                  153
    map[ 3] =                  276
    map[ 4] =                  313
    map[ 5] =                  400
    map[ 6] =                  427
    map[ 7] =                  544
    map[ 8] =                  649
    map[ 9] =                  846
    map[10] =                  881
    map[11] =                  930
    map[12] =                 1005
    map[13] =                 1034
    map[14] =                 1046
    verifying map
    1 2 3 4 5 6 7 8 9 10 11 12 13 14

 3. reading and verifying vartypes

 4. reading and verifying varnames
    verifying varnames unique

 5. reading and verifying sort order
    verifying contents

 6. reading and verifying display formats
    verifying formats
    verifying formats correspond to variable type

 7. reading and verifying value-label assignment
    verifying value-label construction
    verifying value label and corresponding variable types

 8. reading and verifying variable-label assignment
    verifying variable labels construction

 9. reading and verifying characteristics
    (0 characteristics in file)

10. reading and verifying data
    (dtaverify_117 cannot verify that values are correct)
    verifying construction
    (1 strL variables)
    verifying strL construction

11. reading and verifying strLs
    verifying construction
    (3 strLs expected)

12. reading and verifying value label definitions
    verifying construction
    (0 labels in file)

no errors or warnings above; .dta file valid
```

### Installed Versions

<details>
miniforge3\envs\pandas-dev\lib\site-packages\_distutils_hack\__init__.py:26: UserWarning: Setuptools is replacing distutils.
  warnings.warn("Setuptools is replacing distutils.")

INSTALLED VERSIONS
------------------
commit                : da802479fca521b7992fbf76d5984992cd5d495d
python                : 3.10.14.final.0
python-bits           : 64
OS                    : Windows
OS-release            : 10
Version               : 10.0.19045
machine               : AMD64
processor             : Intel64 Family 6 Model 158 Stepping 10, GenuineIntel
byteorder             : little
LC_ALL                : None
LANG                  : None
LOCALE                : English_United Kingdom.1252

pandas                : 3.0.0.dev0+629.gda802479fc
numpy                 : 1.26.4
pytz                  : 2024.1
dateutil              : 2.9.0
setuptools            : 69.2.0
pip                   : 24.0
Cython                : 3.0.9
pytest                : 8.1.1
hypothesis            : 6.99.13
sphinx                : 7.2.6
blosc                 : None
feather               : None
xlsxwriter            : 3.1.9
lxml.etree            : 5.1.0
html5lib              : 1.1
pymysql               : 1.4.6
psycopg2              : 2.9.9
jinja2                : 3.1.3
IPython               : 8.22.2
pandas_datareader     : None
adbc-driver-postgresql: None
adbc-driver-sqlite    : None
bs4                   : 4.12.3
bottleneck            : 1.3.8
fastparquet           : 2024.2.0
fsspec                : 2024.3.1
gcsfs                 : 2024.3.1
matplotlib            : 3.8.3
numba                 : 0.59.1
numexpr               : 2.9.0
odfpy                 : None
openpyxl              : 3.1.2
pyarrow               : 15.0.2
pyreadstat            : 1.2.7
python-calamine       : None
pyxlsb                : 1.0.10
s3fs                  : 2024.3.1
scipy                 : 1.12.0
sqlalchemy            : 2.0.29
tables                : 3.9.2
tabulate              : 0.9.0
xarray                : 2024.2.0
xlrd                  : 2.0.1
zstandard             : 0.22.0
tzdata                : 2024.1
qtpy                  : None
pyqt5                 : None
</details>
