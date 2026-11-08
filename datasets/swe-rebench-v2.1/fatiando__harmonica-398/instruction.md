Coordinates decimal issue in filters
**Description of the problem:**
<!--
Please be as detailed as you can when describing an issue. The more information
we have, the easier it will be for us to track this down.
-->

When using the new grid transformations, I noticed that several (at least `derivative_upward` and `gaussian_lowpass`) functions are slightly changing the easting coordinates of the dataarrays. I was attempting to add the resulting grids as a new dataset variable with:
```python
magnetic_grid_padded['deriv_upward'] = hm.derivative_upward(magnetic_grid_padded)
```
Plotting the new grid shows:
![image](https://user-images.githubusercontent.com/81199856/225128479-bdca1ee7-5873-4d27-89d5-dd97f0726a7f.png)

Compared to the normal method of creating a new array shows an issue with the high and low easting values.
```python
deriv_upward = hm.derivative_upward(magnetic_grid_padded)
```
![image](https://user-images.githubusercontent.com/81199856/225128711-fc0a8e08-b976-4d45-af7e-89f90b86c4a4.png)

Numpy testing confirms that the easting values of the produced grid don't match the original past the 10th decimal place.

```python
np.testing.assert_almost_equal(
    deriv_upward.easting.values,
    magnetic_grid_padded.easting.values,
    decimal=11,
)
```
```
AssertionError:
Arrays are not almost equal to 11 decimals

Mismatched elements: 391 / 576 (67.9%)
Max absolute difference: 1.16415322e-10
Max relative difference: 2.53196054e-16
 x: array([459783.31767976726, 459833.31767976726, 459883.31767976726,
       459933.31767976726, 459983.31767976726, 460033.31767976726,
       460083.31767976726, 460133.31767976726, 460183.31767976726,...
 y: array([459783.31767976715, 459833.31767976715, 459883.31767976715,
       459933.31767976715, 459983.31767976715, 460033.31767976715,
       460083.31767976715, 460133.31767976715, 460183.31767976715,...
```
The northing coordinates are exactly equal for this dataset, but northing and easting both fail the test on a dataset of min.

I have a workaround, which is to round the coordinate values to the same number of decimal places before merging, which gives the desired results.

```python
magnetic_grid_padded = magnetic_grid_padded.assign_coords(
    {
        "easting":np.round(magnetic_grid_padded.easting.values),
        "northing":np.round(magnetic_grid_padded.northing.values)
    })

deriv_upward = hm.derivative_upward(magnetic_grid_padded)
deriv_upward = deriv_upward.assign_coords(
    {
        "easting":np.round(deriv_upward.easting.values),
        "northing":np.round(deriv_upward.northing.values)
    })

magnetic_grid_padded['deriv_upward'] = deriv_upward
```

I need to add the resulting data back to the original dataset since my grid has NaN's, which I've filled with -999 and need to mask the results with the original data extent.

Any ideas what's causing this issue?

Otherwise, these new functions are great!

**System information**

* Operating system: Linux
* Python installation (Anaconda, system, ETS):  mambaforge
* Version of Python: 3.10.9
* Version of this package: 0.6.0.post1+g627fbfa.d20230310
* If using conda, paste the output of `conda list` below:

<details>
<summary>Output of conda list</summary>
<pre>

# Name                    Version                   Build  Channel
_libgcc_mutex             0.1                 conda_forge    conda-forge
_openmp_mutex             4.5                       2_gnu    conda-forge
aiofiles                  22.1.0             pyhd8ed1ab_0    conda-forge
aiosqlite                 0.18.0             pyhd8ed1ab_0    conda-forge
anyio                     3.6.2              pyhd8ed1ab_0    conda-forge
argon2-cffi               21.3.0             pyhd8ed1ab_0    conda-forge
argon2-cffi-bindings      21.2.0          py310h5764c6d_3    conda-forge
asttokens                 2.2.1              pyhd8ed1ab_0    conda-forge
attrs                     22.2.0             pyh71513ae_0    conda-forge
babel                     2.12.1             pyhd8ed1ab_1    conda-forge
backcall                  0.2.0              pyh9f0ad1d_0    conda-forge
backports                 1.0                pyhd8ed1ab_3    conda-forge
backports.functools_lru_cache 1.6.4              pyhd8ed1ab_0    conda-forge
beautifulsoup4            4.11.2             pyha770c72_0    conda-forge
bleach                    6.0.0              pyhd8ed1ab_0    conda-forge
bokeh                     2.4.3              pyhd8ed1ab_3    conda-forge
boule                     0.4.1              pyhd8ed1ab_0    conda-forge
brotli                    1.0.9                h166bdaf_8    conda-forge
brotli-bin                1.0.9                h166bdaf_8    conda-forge
brotlipy                  0.7.0           py310h5764c6d_1005    conda-forge
bzip2                     1.0.8                h7f98852_4    conda-forge
c-ares                    1.18.1               h7f98852_0    conda-forge
ca-certificates           2022.12.7            ha878542_0    conda-forge
cached-property           1.5.2                hd8ed1ab_1    conda-forge
cached_property           1.5.2              pyha770c72_1    conda-forge
cartopy                   0.21.1          py310hcb7e713_0    conda-forge
certifi                   2022.12.7          pyhd8ed1ab_0    conda-forge
cffi                      1.15.1          py310h255011f_3    conda-forge
cftime                    1.6.2           py310hde88566_1    conda-forge
charset-normalizer        2.1.1              pyhd8ed1ab_0    conda-forge
click                     8.1.3           unix_pyhd8ed1ab_2    conda-forge
cloudpickle               2.2.1              pyhd8ed1ab_0    conda-forge
comm                      0.1.2              pyhd8ed1ab_0    conda-forge
contourpy                 1.0.7           py310hdf3cbec_0    conda-forge
cryptography              39.0.2          py310h34c0648_0    conda-forge
curl                      7.88.1               hdc1c0ab_0    conda-forge
cycler                    0.11.0             pyhd8ed1ab_0    conda-forge
cytoolz                   0.12.0          py310h5764c6d_1    conda-forge
dask                      2023.3.0           pyhd8ed1ab_0    conda-forge
dask-core                 2023.3.0           pyhd8ed1ab_0    conda-forge
debugpy                   1.6.6           py310heca2aa9_0    conda-forge
decorator                 5.1.1              pyhd8ed1ab_0    conda-forge
defusedxml                0.7.1              pyhd8ed1ab_0    conda-forge
distributed               2023.3.0           pyhd8ed1ab_0    conda-forge
docrep                    0.3.2              pyh44b312d_0    conda-forge
ensaio                    0.5.0              pyhd8ed1ab_0    conda-forge
entrypoints               0.4                pyhd8ed1ab_0    conda-forge
executing                 1.2.0              pyhd8ed1ab_0    conda-forge
flit-core                 3.8.0              pyhd8ed1ab_0    conda-forge
fonttools                 4.39.0          py310h1fa729e_0    conda-forge
freetype                  2.12.1               hca18f0e_1    conda-forge
fsspec                    2023.3.0           pyhd8ed1ab_1    conda-forge
future                    0.18.3             pyhd8ed1ab_0    conda-forge
geos                      3.11.1               h27087fc_0    conda-forge
h5netcdf                  1.1.0              pyhd8ed1ab_1    conda-forge
h5py                      3.8.0           nompi_py310h0311031_100    conda-forge
harmonica                 0.6.0.post1+g627fbfa.d20230310          pypi_0    pypi
hdf4                      4.2.15               h501b40f_6    conda-forge
hdf5                      1.12.2          nompi_h4df4325_101    conda-forge
heapdict                  1.0.1                      py_0    conda-forge
icu                       70.1                 h27087fc_0    conda-forge
idna                      3.4                pyhd8ed1ab_0    conda-forge
importlib-metadata        6.0.0              pyha770c72_0    conda-forge
importlib_metadata        6.0.0                hd8ed1ab_0    conda-forge
importlib_resources       5.12.0             pyhd8ed1ab_0    conda-forge
ipykernel                 6.21.3             pyh210e3f2_0    conda-forge
ipython                   8.11.0             pyh41d4057_0    conda-forge
ipython_genutils          0.2.0                      py_1    conda-forge
jedi                      0.18.2             pyhd8ed1ab_0    conda-forge
jinja2                    3.1.2              pyhd8ed1ab_1    conda-forge
joblib                    1.2.0              pyhd8ed1ab_0    conda-forge
json5                     0.9.5              pyh9f0ad1d_0    conda-forge
jsonschema                4.17.3             pyhd8ed1ab_0    conda-forge
jupyter_client            8.0.3              pyhd8ed1ab_0    conda-forge
jupyter_core              5.2.0           py310hff52083_0    conda-forge
jupyter_events            0.6.3              pyhd8ed1ab_0    conda-forge
jupyter_server            2.4.0              pyhd8ed1ab_0    conda-forge
jupyter_server_fileid     0.8.0              pyhd8ed1ab_0    conda-forge
jupyter_server_terminals  0.4.4              pyhd8ed1ab_1    conda-forge
jupyter_server_ydoc       0.6.1              pyhd8ed1ab_0    conda-forge
jupyter_ydoc              0.2.2              pyhd8ed1ab_0    conda-forge
jupyterlab                3.6.1              pyhd8ed1ab_0    conda-forge
jupyterlab_pygments       0.2.2              pyhd8ed1ab_0    conda-forge
jupyterlab_server         2.20.0             pyhd8ed1ab_0    conda-forge
keyutils                  1.6.1                h166bdaf_0    conda-forge
kiwisolver                1.4.4           py310hbf28c38_1    conda-forge
krb5                      1.20.1               h81ceb04_0    conda-forge
lcms2                     2.15                 haa2dc70_1    conda-forge
ld_impl_linux-64          2.40                 h41732ed_0    conda-forge
lerc                      4.0.0                h27087fc_0    conda-forge
libaec                    1.0.6                hcb278e6_1    conda-forge
libblas                   3.9.0           16_linux64_openblas    conda-forge
libbrotlicommon           1.0.9                h166bdaf_8    conda-forge
libbrotlidec              1.0.9                h166bdaf_8    conda-forge
libbrotlienc              1.0.9                h166bdaf_8    conda-forge
libcblas                  3.9.0           16_linux64_openblas    conda-forge
libcurl                   7.88.1               hdc1c0ab_0    conda-forge
libdeflate                1.17                 h0b41bf4_0    conda-forge
libedit                   3.1.20191231         he28a2e2_2    conda-forge
libev                     4.33                 h516909a_1    conda-forge
libffi                    3.4.2                h7f98852_5    conda-forge
libgcc-ng                 12.2.0              h65d4601_19    conda-forge
libgfortran-ng            12.2.0              h69a702a_19    conda-forge
libgfortran5              12.2.0              h337968e_19    conda-forge
libgomp                   12.2.0              h65d4601_19    conda-forge
libiconv                  1.17                 h166bdaf_0    conda-forge
libjpeg-turbo             2.1.5.1              h0b41bf4_0    conda-forge
liblapack                 3.9.0           16_linux64_openblas    conda-forge
libllvm11                 11.1.0               he0ac6c6_5    conda-forge
libnetcdf                 4.9.1           nompi_hd2e9713_102    conda-forge
libnghttp2                1.52.0               h61bc06f_0    conda-forge
libnsl                    2.0.0                h7f98852_0    conda-forge
libopenblas               0.3.21          pthreads_h78a6416_3    conda-forge
libpng                    1.6.39               h753d276_0    conda-forge
libsodium                 1.0.18               h36c2ea0_1    conda-forge
libsqlite                 3.40.0               h753d276_0    conda-forge
libssh2                   1.10.0               hf14f497_3    conda-forge
libstdcxx-ng              12.2.0              h46fd767_19    conda-forge
libtiff                   4.5.0                hddfeb54_5    conda-forge
libuuid                   2.32.1            h7f98852_1000    conda-forge
libwebp-base              1.2.4                h166bdaf_0    conda-forge
libxcb                    1.13              h7f98852_1004    conda-forge
libxml2                   2.10.3               h7463322_0    conda-forge
libzip                    1.9.2                hc929e4a_1    conda-forge
libzlib                   1.2.13               h166bdaf_4    conda-forge
llvmlite                  0.39.1          py310h58363a5_1    conda-forge
locket                    1.0.0              pyhd8ed1ab_0    conda-forge
lz4                       4.3.2           py310h0cfdcf0_0    conda-forge
lz4-c                     1.9.4                hcb278e6_0    conda-forge
markupsafe                2.1.2           py310h1fa729e_0    conda-forge
matplotlib-base           3.7.1           py310he60537e_0    conda-forge
matplotlib-inline         0.1.6              pyhd8ed1ab_0    conda-forge
mistune                   2.0.5              pyhd8ed1ab_0    conda-forge
msgpack-python            1.0.5           py310hdf3cbec_0    conda-forge
munkres                   1.1.4              pyh9f0ad1d_0    conda-forge
nbclassic                 0.5.3              pyhb4ecaf3_3    conda-forge
nbclient                  0.7.2              pyhd8ed1ab_0    conda-forge
nbconvert                 7.2.9              pyhd8ed1ab_0    conda-forge
nbconvert-core            7.2.9              pyhd8ed1ab_0    conda-forge
nbconvert-pandoc          7.2.9              pyhd8ed1ab_0    conda-forge
nbformat                  5.7.3              pyhd8ed1ab_0    conda-forge
ncurses                   6.3                  h27087fc_1    conda-forge
nest-asyncio              1.5.6              pyhd8ed1ab_0    conda-forge
netcdf4                   1.6.3           nompi_py310h0feb132_100    conda-forge
notebook                  6.5.3              pyha770c72_0    conda-forge
notebook-shim             0.2.2              pyhd8ed1ab_0    conda-forge
numba                     0.56.4          py310ha5257ce_0    conda-forge
numpy                     1.23.5          py310h53a5b5f_0    conda-forge
openjpeg                  2.5.0                hfec8fc6_2    conda-forge
openssl                   3.0.8                h0b41bf4_0    conda-forge
packaging                 23.0               pyhd8ed1ab_0    conda-forge
pandas                    1.5.3           py310h9b08913_0    conda-forge
pandoc                    2.19.2               h32600fe_2    conda-forge
pandocfilters             1.5.0              pyhd8ed1ab_0    conda-forge
parso                     0.8.3              pyhd8ed1ab_0    conda-forge
partd                     1.3.0              pyhd8ed1ab_0    conda-forge
pexpect                   4.8.0              pyh1a96a4e_2    conda-forge
pickleshare               0.7.5                   py_1003    conda-forge
pillow                    9.4.0           py310h065c6d2_2    conda-forge
pip                       23.0.1             pyhd8ed1ab_0    conda-forge
pkgutil-resolve-name      1.3.10             pyhd8ed1ab_0    conda-forge
platformdirs              3.1.0              pyhd8ed1ab_0    conda-forge
pooch                     1.7.0              pyhd8ed1ab_0    conda-forge
proj                      9.1.1                h8ffa02c_2    conda-forge
prometheus_client         0.16.0             pyhd8ed1ab_0    conda-forge
prompt-toolkit            3.0.38             pyha770c72_0    conda-forge
prompt_toolkit            3.0.38               hd8ed1ab_0    conda-forge
psutil                    5.9.4           py310h5764c6d_0    conda-forge
pthread-stubs             0.4               h36c2ea0_1001    conda-forge
ptyprocess                0.7.0              pyhd3deb0d_0    conda-forge
pure_eval                 0.2.2              pyhd8ed1ab_0    conda-forge
pycparser                 2.21               pyhd8ed1ab_0    conda-forge
pygments                  2.14.0             pyhd8ed1ab_0    conda-forge
pyopenssl                 23.0.0             pyhd8ed1ab_0    conda-forge
pyparsing                 3.0.9              pyhd8ed1ab_0    conda-forge
pyproj                    3.4.1           py310h15e2413_1    conda-forge
pyrsistent                0.19.3          py310h1fa729e_0    conda-forge
pyshp                     2.3.1              pyhd8ed1ab_0    conda-forge
pysocks                   1.7.1              pyha2e5f31_6    conda-forge
python                    3.10.9          he550d4f_0_cpython    conda-forge
python-dateutil           2.8.2              pyhd8ed1ab_0    conda-forge
python-fastjsonschema     2.16.3             pyhd8ed1ab_0    conda-forge
python-json-logger        2.0.7              pyhd8ed1ab_0    conda-forge
python_abi                3.10                    3_cp310    conda-forge
pytz                      2022.7.1           pyhd8ed1ab_0    conda-forge
pyyaml                    6.0             py310h5764c6d_5    conda-forge
pyzmq                     25.0.0          py310h059b190_0    conda-forge
readline                  8.1.2                h0f457ee_0    conda-forge
requests                  2.28.2             pyhd8ed1ab_0    conda-forge
rfc3339-validator         0.1.4              pyhd8ed1ab_0    conda-forge
rfc3986-validator         0.1.1              pyh9f0ad1d_0    conda-forge
scikit-learn              1.2.2           py310h209a8ca_0    conda-forge
scipy                     1.10.1          py310h8deb116_0    conda-forge
send2trash                1.8.0              pyhd8ed1ab_0    conda-forge
setuptools                67.6.0             pyhd8ed1ab_0    conda-forge
shapely                   2.0.1           py310h8b84c32_0    conda-forge
six                       1.16.0             pyh6c4a22f_0    conda-forge
sniffio                   1.3.0              pyhd8ed1ab_0    conda-forge
sortedcontainers          2.4.0              pyhd8ed1ab_0    conda-forge
soupsieve                 2.3.2.post1        pyhd8ed1ab_0    conda-forge
sqlite                    3.40.0               h4ff8645_0    conda-forge
stack_data                0.6.2              pyhd8ed1ab_0    conda-forge
tblib                     1.7.0              pyhd8ed1ab_0    conda-forge
terminado                 0.17.1             pyh41d4057_0    conda-forge
threadpoolctl             3.1.0              pyh8a188c0_0    conda-forge
tinycss2                  1.2.1              pyhd8ed1ab_0    conda-forge
tk                        8.6.12               h27826a3_0    conda-forge
tomli                     2.0.1              pyhd8ed1ab_0    conda-forge
toolz                     0.12.0             pyhd8ed1ab_0    conda-forge
tornado                   6.2             py310h5764c6d_1    conda-forge
traitlets                 5.9.0              pyhd8ed1ab_0    conda-forge
typing-extensions         4.4.0                hd8ed1ab_0    conda-forge
typing_extensions         4.4.0              pyha770c72_0    conda-forge
tzdata                    2022g                h191b570_0    conda-forge
unicodedata2              15.0.0          py310h5764c6d_0    conda-forge
urllib3                   1.26.14            pyhd8ed1ab_0    conda-forge
verde                     1.7.0              pyhd8ed1ab_0    conda-forge
wcwidth                   0.2.6              pyhd8ed1ab_0    conda-forge
webencodings              0.5.1                      py_1    conda-forge
websocket-client          1.5.1              pyhd8ed1ab_0    conda-forge
wheel                     0.38.4             pyhd8ed1ab_0    conda-forge
xarray                    2023.2.0           pyhd8ed1ab_0    conda-forge
xorg-libxau               1.0.9                h7f98852_0    conda-forge
xorg-libxdmcp             1.1.3                h7f98852_0    conda-forge
xrft                      1.0.1                    pypi_0    pypi
xz                        5.2.6                h166bdaf_0    conda-forge
y-py                      0.5.9           py310h4426083_0    conda-forge
yaml                      0.2.5                h7f98852_2    conda-forge
ypy-websocket             0.8.2              pyhd8ed1ab_0    conda-forge
zeromq                    4.3.4                h9c3ff4c_1    conda-forge
zict                      2.2.0              pyhd8ed1ab_0    conda-forge
zipp                      3.15.0             pyhd8ed1ab_0    conda-forge
zstd                      1.5.2                h3eb15da_6    conda-forge

</pre>
</details>
