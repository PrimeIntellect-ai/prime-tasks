Can't Parse Cross Section Data From Serpent 2.1.32
## Summary of issue
I am getting `ValueError: Unidentifiable entry` when trying to load my `*_xs0.m` file, because `serpentTools` doesn't know what to do with entries suffixed by `pspec`.  These appear to be new to Serpent 2.1.32, and the code runs fine when I manually remove all entries suffixed by `pspec`.  However, the code still exits non-zero when I turn off raising errors and attempt to skip the pre-check with the `pspec` entries still there.

## Code for reproducing the issue
Obviously, the path is different, and the file I've taken straight from Serpent is [main.input.inp_xs0.m.txt](https://github.com/CORE-GATECH-GROUP/serpent-tools/files/6780212/main.input.inp_xs0.m.txt).  Also, I had to add the `*.txt` extension so that GitHub would allow me to upload.
```
import serpentTools
serpentTools.settings.rc["sampler.raiseErrors"] = False
serpentTools.settings.rc["sampler.skipPrecheck"] = True
serpentTools.settings.rc["serpentVersion"] = '2.1.32'
xsreader = serpentTools.read('/home/ec2-user/PyCharm_KACEGEN/test/serpent/endfb71_mcnp/main.input.inp_xs0.m')
```

## Actual outcome including console output and error traceback if applicable
```
Traceback (most recent call last):
  File "/usr/local/lib/python3.7/site-packages/serpentTools-0.9.4rc0-py3.7.egg/serpentTools/parsers/xsplot.py", line 149, in _read
    raise ValueError("Unidentifiable entry\n{}".format(chunk))
ValueError: Unidentifiable entry
['i36085_82c_pspec = [\n', '5.13997E-01 4.34000E-03\n', '1.33539E-02 1.02414E-05\n', '1.32919E-02 5.32352E-06\n', '1.49217E-02 1.48786E-06\n', '1.49123E-02 7.63269E-07\n', '1.68737E-03 4.61757E-07\n', '1.75360E-03 2.45265E-07\n', '1.51392E-02 1.60258E-07\n', '1.50285E-03 1.33284E-07\n', '1.51383E-02 8.31602E-08\n', '1.51180E-01 2.17000E-08\n', '3.62810E-01 2.17000E-08\n', '1.94166E-03 4.43158E-09\n', '1.50414E-02 3.50630E-09\n', '1.50398E-02 2.45196E-09\n', '1.29810E-01 2.17000E-09\n']

```
## Expected outcome
I expected to be able to follow [the tutorial](https://serpent-tools.readthedocs.io/en/master/examples/XSPlot.html).

## Versions
* Serpent 2.1.32
* serpentTools 0.9.4rc0
* Python 3.7.6
