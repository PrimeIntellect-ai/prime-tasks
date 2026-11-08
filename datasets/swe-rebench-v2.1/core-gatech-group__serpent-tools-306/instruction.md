BUG ADFs in results file fail in numeric conversion
## Summary of issue
When reading a file with assembly discontinuity factors (ADFs), there is a string that serpentTools attempts to convert to a vector. This causes a ValueError
## Code for reproducing the issue
Add the following code to a section of a result file
```
% Assembly discontinuity factors (order: W-S-E-N / NW-NE-SE-SW):

DF_SURFACE                (idx, [1:  3])  = 'ADF' ;
DF_SYM                    (idx, 1)        = 1 ;
DF_N_SURF                 (idx, 1)        = 4 ;
DF_N_CORN                 (idx, 1)        = 4 ;
```
```
$ python -c "import serpentTools; serpentTools.read(\"adf_res.m\")"
```
## Actual outcome including console output and error traceback if applicable
```
Traceback (most recent call last):
  File "<string>", line 1, in <module>
  File "/home/ajohnson400/.local/lib/python3.7/site-packages/serpentTools/parsers/__init__.py", line 155, in read
    returnedFromLoader.read()
  File "/home/ajohnson400/.local/lib/python3.7/site-packages/serpentTools/parsers/base.py", line 52, in read
    self._read()
  File "/home/ajohnson400/.local/lib/python3.7/site-packages/serpentTools/parsers/results.py", line 158, in _read
    self._processResults(tline)
  File "/home/ajohnson400/.local/lib/python3.7/site-packages/serpentTools/parsers/results.py", line 176, in _processResults
    self._storeUnivData(varNameSer, varVals)
  File "/home/ajohnson400/.local/lib/python3.7/site-packages/serpentTools/parsers/results.py", line 198, in _storeUnivData
    values = str2vec(varVals)  # convert the string to float numbers
  File "/home/ajohnson400/.local/lib/python3.7/site-packages/serpentTools/utils/core.py", line 59, in str2vec
    return out([of(xx) for xx in vec])
  File "/home/ajohnson400/.local/lib/python3.7/site-packages/serpentTools/utils/core.py", line 59, in <listcomp>
    return out([of(xx) for xx in vec])
ValueError: could not convert string to float: 'ADF'
```
## Expected outcome
Doesn't fail
## Versions

* Version  from ``serpentTools.__version__`` `0.7.0rc0`

* Python version - ``python --version`` `3.7`
