BUG Branching Reader fails with uncertainties
## Summary of issue
When reading a file with uncertainties, and the `branching.areUncsPresent` setting is `True`, the code
errors.
Also, I think we can eliminate this setting entirely, because when a file has uncertainties,  the value N still indicates the number of groups/values present without uncertainties.
https://github.com/CORE-GATECH-GROUP/serpent-tools/blob/0e61685f19f644b9bb7a1c2a2b3d8aec30ffcaf5/serpentTools/data/demo.coe#L6-L13
From the [SERPENT wiki](http://serpent.vtt.fi/mediawiki/index.php/Automated_burnup_sequence#Output):
```
The relative statistical errors are not printed by default, but they can be included with an option in the
set coefpara card, which also defines list of parameters included in the output. In such case the data is
provided in mean value - statistical error pairs and N gives the number of pairs.
```

## Code for reproducing the issue
```
>>> import serpentTools
>>> serpentTools.settings.rc['branching.areUncsPresent'] = True
>>> serpentTools.readDataFile('demo.coe')
```
## Actual outcome including console output and error traceback if applicable
```
Traceback (most recent call last):
  File "test.py", line 3, in <module>
    serpentTools.readDataFile('demo.coe')
  File "/home/ajohnson400/github/my-serpent-tools/serpentTools/data/__init__.py", line 76, in readDataFile
    return read(filePath, **kwargs)
  File "/home/ajohnson400/github/my-serpent-tools/serpentTools/parsers/__init__.py", line 155, in read
    returnedFromLoader.read()
  File "/home/ajohnson400/github/my-serpent-tools/serpentTools/parsers/base.py", line 52, in read
    self._read()
  File "/home/ajohnson400/github/my-serpent-tools/serpentTools/parsers/branching.py", line 42, in _read
    self._processBranchBlock()
  File "/home/ajohnson400/github/my-serpent-tools/serpentTools/parsers/branching.py", line 69, in _processBranchBlock
    self._whereAmI['buIndx'])
  File "/home/ajohnson400/github/my-serpent-tools/serpentTools/parsers/branching.py", line 121, in _processBranchUniverses
    univ.addData(varName, array(vals), uncertaity=False)
TypeError: addData() got an unexpected keyword argument 'uncertaity'
```
## Expected outcome
Code does not fail. Even better, code can infer when the output file has uncertainties or not

## Versions

* Version  from ``serpentTools.__version__`` `0.6.1+55.g0e6185` (develop) and `0.6.1` (release)

* Python version - ``python --version`` `3.7.1`

### Additional contract requirements

The branching reader must determine from the coefficient file whether values are stored as mean/statistical-error pairs. Files without such pairs must be read as ordinary coefficient data, and users must not need to configure whether uncertainties are present.
