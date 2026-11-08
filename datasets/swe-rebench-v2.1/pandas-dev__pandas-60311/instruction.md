BUG: Disabling pandas option display.html.use_mathjax has no effect
### Pandas version checks

- [X] I have checked that this issue has not already been reported.

- [X] I have confirmed this bug exists on the [latest version](https://pandas.pydata.org/docs/whatsnew/index.html) of pandas.

- [ ] I have confirmed this bug exists on the [main branch](https://pandas.pydata.org/docs/dev/getting_started/install.html#installing-the-development-version-of-pandas) of pandas.


### Reproducible Example

```python
import pandas as pd
pd.set_option('display.html.use_mathjax', False)
pd.DataFrame([
    "$2.13 dont_make_this_math $5.24"
])
```


### Issue Description

My pandas data frames contain text columns which contain dollar signs. I need to be represented as raw strings not as a math-formatted picture.

Pandas provides the option `display.html.use_mathjax` to this end. However, setting the option does not change pandas behavior. Even with the config set the string "$2.13 dont_make_this_math $5.24" has its spaces removed and text after `_` subscripted.

I understand this can be managed by explicitly escaping dollar signs in any text column I come across, but this is a lot of overhead.

### Expected Behavior

![Screenshot 2024-09-25 at 10 52 27](https://github.com/user-attachments/assets/c4ada236-1ded-4c99-8f9c-1675f7a49a71)

not as

![Screenshot 2024-09-25 at 10 52 18](https://github.com/user-attachments/assets/014efb65-f851-4b17-9b36-6b21473153bd)

### Installed Versions

<details>

INSTALLED VERSIONS
------------------
commit                : 0691c5cf90477d3503834d983f69350f250a6ff7
python                : 3.11.9
python-bits           : 64
OS                    : Darwin
OS-release            : 23.6.0
Version               : Darwin Kernel Version 23.6.0: Mon Jul 29 21:14:30 PDT 2024; root:xnu-10063.141.2~1/RELEASE_ARM64_T6000
machine               : arm64
processor             : arm
byteorder             : little
LC_ALL                : None
LANG                  : en_US.UTF-8
LOCALE                : en_US.UTF-8

pandas                : 2.2.3
numpy                 : 1.26.4
pytz                  : 2024.1
dateutil              : 2.9.0.post0
pip                   : 23.3.1
Cython                : None
sphinx                : None
IPython               : 8.27.0
adbc-driver-postgresql: None
adbc-driver-sqlite    : None
bs4                   : 4.12.3
blosc                 : None
bottleneck            : None
dataframe-api-compat  : None
fastparquet           : None
fsspec                : None
html5lib              : None
hypothesis            : None
gcsfs                 : None
jinja2                : 3.1.4
lxml.etree            : None
matplotlib            : 3.9.2
numba                 : None
numexpr               : None
odfpy                 : None
openpyxl              : None
pandas_gbq            : None
psycopg2              : None
pymysql               : None
pyarrow               : 15.0.2
pyreadstat            : None
pytest                : None
python-calamine       : None
pyxlsb                : None
s3fs                  : None
scipy                 : None
sqlalchemy            : None
tables                : None
tabulate              : None
xarray                : None
xlrd                  : None
xlsxwriter            : None
zstandard             : None
tzdata                : 2024.1
qtpy                  : None
pyqt5                 : None
</details>

### Additional contract requirements

- When the pandas option ``display.html.use_mathjax`` is set to ``False``, the HTML
  returned by ``DataFrame._repr_html_()`` must include the CSS class token
  ``mathjax_ignore`` on the rendered table (in addition to the existing
  ``tex2jax_ignore`` token), so that MathJax leaves the cell text untouched.
- When ``display.html.use_mathjax`` is ``True`` (the default), the HTML returned by
  ``DataFrame._repr_html_()`` must not include the ``mathjax_ignore`` class token.
