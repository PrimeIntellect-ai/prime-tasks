[BUG] grayskull detects too many licenses when using sdist or GitHub url
**Describe the bug**
When running grayskull on a GitHub repo or sdist for a package using setuptools-scm (not sure this is only due to that), licenses under `.eggs` are detected and added to the `meta.yaml`.

**To Reproduce**
Steps to reproduce the behavior:
1. grayskull pypi --strict-conda-forge https://github.com/MaxIV-KitsControls/lib-maxiv-pandaboxlib -t 1.0.5

or:

1. git clone https://github.com/MaxIV-KitsControls/lib-maxiv-pandaboxlib.git
2. cd lib-maxiv-pandaboxlib/
3. git checkout 1.0.5
4. python -m build .
5. cd dist
6. grayskull pypi --strict-conda-forge pandaboxlib-1.0.5.tar.gz


**Expected behavior**
Only the license of the package should be detected. `.eggs` should be excluded.

**Outputs**

```yaml
about:
  home: https://github.com/MaxIV-KitsControls/lib-maxiv-pandaboxlib
  summary: Library for communication with PandABox.This communication is based in TCP/IP sockets.
  license: Apache-2.0 & MIT & LGPL-3.0
  license_file:
    - LICENSE.txt
    - .eggs/typing_extensions-4.4.0-py3.9.egg/EGG-INFO/LICENSE
    - .eggs/setuptools_scm-7.0.5-py3.9.egg/EGG-INFO/LICENSE
```

**Environment:**
 - conda list

```
# packages in environment at /grayskull:
#
# Name                    Version                   Build  Channel
_libgcc_mutex             0.1                 conda_forge    conda-forge
_openmp_mutex             4.5                       2_gnu    conda-forge
alabaster                 0.7.12                     py_0    conda-forge
babel                     2.10.3             pyhd8ed1ab_0    conda-forge
brotlipy                  0.7.0           py39hb9d737c_1004    conda-forge
build                     0.7.0              pyhd8ed1ab_0    conda-forge
bzip2                     1.0.8                h7f98852_4    conda-forge
c-ares                    1.18.1               h7f98852_0    conda-forge
ca-certificates           2022.6.15            ha878542_0    conda-forge
certifi                   2022.6.15        py39hf3d152e_0    conda-forge
cffi                      1.15.1           py39he91dace_0    conda-forge
charset-normalizer        2.1.0              pyhd8ed1ab_0    conda-forge
colorama                  0.4.5              pyhd8ed1ab_0    conda-forge
conda-souschef            2.2.3                    pypi_0    pypi
cryptography              37.0.2           py39hd97740a_0    conda-forge
curl                      7.83.1               h7bff187_0    conda-forge
docutils                  0.18.1           py39hf3d152e_1    conda-forge
expat                     2.4.8                h27087fc_0    conda-forge
gettext                   0.19.8.1          h73d1719_1008    conda-forge
git                       2.37.0          pl5321h36853c3_0    conda-forge
grayskull                 1.8.3                    pypi_0    pypi
idna                      3.3                pyhd8ed1ab_0    conda-forge
imagesize                 1.4.1              pyhd8ed1ab_0    conda-forge
importlib-metadata        4.11.4           py39hf3d152e_0    conda-forge
jarowinkler               1.1.0            py39h5a03fae_0    conda-forge
jinja2                    3.1.2              pyhd8ed1ab_1    conda-forge
keyutils                  1.6.1                h166bdaf_0    conda-forge
krb5                      1.19.3               h3790be6_0    conda-forge
ld_impl_linux-64          2.36.1               hea4e1c9_2    conda-forge
libblas                   3.9.0           15_linux64_openblas    conda-forge
libcblas                  3.9.0           15_linux64_openblas    conda-forge
libcurl                   7.83.1               h7bff187_0    conda-forge
libedit                   3.1.20191231         he28a2e2_2    conda-forge
libev                     4.33                 h516909a_1    conda-forge
libffi                    3.4.2                h7f98852_5    conda-forge
libgcc-ng                 12.1.0              h8d9b700_16    conda-forge
libgfortran-ng            12.1.0              h69a702a_16    conda-forge
libgfortran5              12.1.0              hdcd56e2_16    conda-forge
libgomp                   12.1.0              h8d9b700_16    conda-forge
libiconv                  1.16                 h516909a_0    conda-forge
liblapack                 3.9.0           15_linux64_openblas    conda-forge
libnghttp2                1.47.0               h727a467_0    conda-forge
libnsl                    2.0.0                h7f98852_0    conda-forge
libopenblas               0.3.20          pthreads_h78a6416_0    conda-forge
libssh2                   1.10.0               ha56f1ee_2    conda-forge
libstdcxx-ng              12.1.0              ha89aaad_16    conda-forge
libuuid                   2.32.1            h7f98852_1000    conda-forge
libzlib                   1.2.12               h166bdaf_1    conda-forge
markupsafe                2.1.1            py39hb9d737c_1    conda-forge
ncurses                   6.3                  h27087fc_1    conda-forge
numpy                     1.23.0           py39hba7629e_0    conda-forge
openssl                   1.1.1p               h166bdaf_0    conda-forge
packaging                 21.3               pyhd8ed1ab_0    conda-forge
pcre2                     10.37                h032f7d1_0    conda-forge
pep517                    0.12.0           py39hf3d152e_2    conda-forge
perl                      5.32.1          2_h7f98852_perl5    conda-forge
pip                       22.1.2             pyhd8ed1ab_0    conda-forge
pkginfo                   1.8.3              pyhd8ed1ab_0    conda-forge
progressbar2              4.0.0              pyhd8ed1ab_0    conda-forge
pycparser                 2.21               pyhd8ed1ab_0    conda-forge
pygments                  2.12.0             pyhd8ed1ab_0    conda-forge
pyopenssl                 22.0.0             pyhd8ed1ab_0    conda-forge
pyparsing                 3.0.9              pyhd8ed1ab_0    conda-forge
pysocks                   1.7.1            py39hf3d152e_5    conda-forge
python                    3.9.13          h9a8a25e_0_cpython    conda-forge
python-utils              3.3.3              pyhd8ed1ab_0    conda-forge
python_abi                3.9                      2_cp39    conda-forge
pytz                      2022.1             pyhd8ed1ab_0    conda-forge
rapidfuzz                 2.1.2            py39h1832856_0    conda-forge
readline                  8.1.2                h0f457ee_0    conda-forge
requests                  2.28.1             pyhd8ed1ab_0    conda-forge
ruamel.yaml               0.17.21          py39hb9d737c_1    conda-forge
ruamel.yaml.clib          0.2.6            py39hb9d737c_1    conda-forge
ruamel.yaml.jinja2        0.2.4                      py_1    conda-forge
setuptools                63.1.0           py39hf3d152e_0    conda-forge
snowballstemmer           2.2.0              pyhd8ed1ab_0    conda-forge
sphinx                    5.0.2              pyh6c4a22f_0    conda-forge
sphinxcontrib-applehelp   1.0.2                      py_0    conda-forge
sphinxcontrib-devhelp     1.0.2                      py_0    conda-forge
sphinxcontrib-htmlhelp    2.0.0              pyhd8ed1ab_0    conda-forge
sphinxcontrib-jsmath      1.0.1                      py_0    conda-forge
sphinxcontrib-qthelp      1.0.3                      py_0    conda-forge
sphinxcontrib-serializinghtml 1.1.5              pyhd8ed1ab_2    conda-forge
sqlite                    3.39.0               h4ff8645_0    conda-forge
stdlib-list               0.7.0                      py_2    conda-forge
tk                        8.6.12               h27826a3_0    conda-forge
tomli                     2.0.1              pyhd8ed1ab_0    conda-forge
tomli-w                   1.0.0                    pypi_0    pypi
tzdata                    2022a                h191b570_0    conda-forge
urllib3                   1.26.9             pyhd8ed1ab_0    conda-forge
wheel                     0.37.1             pyhd8ed1ab_0    conda-forge
xz                        5.2.5                h516909a_1    conda-forge
zipp                      3.8.0              pyhd8ed1ab_0    conda-forge
zlib                      1.2.12               h166bdaf_1    conda-forge
```
