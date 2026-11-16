LightCurve.baseline(offset_correction=True) throws and exception with to much GTIs
When calling LightCurve.baseline(offset_correction=True) an exception is thrown:

Message: Improper input: N=1 must not exceed M=0

Dave get_lightcurve parameters:
-"filename":"/Users/ricardo/TimeLab/PN_evt.fits" ->
 Download it here: (https://drive.google.com/file/d/1BWx598pXEBvcG_RYY7FnJRcEkI7EI9Aq/view?usp=sharing)

-"meanflux_opts":{"niter":10,"lam":1000,"p":0.01},
-"filters": {"table":"EVENTS","column":"TIME","from":9053,"to":9468}, this filters is not necessary, the exception is thrown every time that we use multiple GTIs
-"dt":1 second

StackTrace
File "/Users/ricardo/TimeLab/dave/src/main/python/stingray/lightcurve.py", line 477, in baseline
Python:  File "/Users/ricardo/TimeLab/dave/src/main/python/stingray/utils.py", line 510, in baseline_als
Python:  File "/Users/ricardo/TimeLab/dave/src/main/python/stingray/utils.py", line 402, in offset_fit
Python:  File "/Users/ricardo/TimeLab/dave/work/miniconda/envs/dave/lib/python3.5/site-packages/scipy/optimize/minpack.py", line 742, in curve_fit
Python:  File "/Users/ricardo/TimeLab/dave/work/miniconda/envs/dave/lib/python3.5/site-packages/scipy/optimize/minpack.py", line 380, in leastsq
Python:  raise TypeError('Improper input: N=%s must not exceed M=%s' % (n, m))

### Additional contract requirements

- For a four-bin light curve, calling `LightCurve.baseline(10000, 0.01, offset_correction=True)` must emit a `UserWarning` whose message contains `Too few bins to perform baseline offset correction`.
