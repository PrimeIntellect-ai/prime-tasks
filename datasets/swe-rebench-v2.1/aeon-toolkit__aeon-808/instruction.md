[BUG] Inverse transform uses method that has been refactored
### Describe the bug

whilst writing a test for BaseCollectionTransformer realised inverse_transform calls

       X_inner = self.preprocess_collection(X)

instead of
       [HIDDEN]






### Steps/Code to reproduce the bug

```python
    d = _Dummy()
    x, _ = make_3d_test_data()
    d.fit(x)
    d.set_tags(**{"skip-inverse-transform": True})
    x2 = d.inverse_transform(x)
    assert_almost_equal(x, x2)


### Expected results

pass test

### Actual results

```python-traceback
Traceback (most recent call last):
  File "C:\Program Files\JetBrains\PyCharm 2022.2.2\plugins\python\helpers\pycharm\_jb_unittest_runner.py", line 35, in <module>
    sys.exit(main(argv=args, module=None, testRunner=unittestpy.TeamcityTestRunner, buffer=not JB_DISABLE_BUFFERING))
  File "C:\Users\Tony Bagnall\AppData\Local\Programs\Python\Python39\lib\unittest\main.py", line 100, in __init__
    self.parseArgs(argv)
  File "C:\Users\Tony Bagnall\AppData\Local\Programs\Python\Python39\lib\unittest\main.py", line 147, in parseArgs
    self.createTests()
  File "C:\Users\Tony Bagnall\AppData\Local\Programs\Python\Python39\lib\unittest\main.py", line 158, in createTests
    self.test = self.testLoader.loadTestsFromNames(self.testNames,
  File "C:\Users\Tony Bagnall\AppData\Local\Programs\Python\Python39\lib\unittest\loader.py", line 220, in loadTestsFromNames
    suites = [self.loadTestsFromName(name, module) for name in names]
  File "C:\Users\Tony Bagnall\AppData\Local\Programs\Python\Python39\lib\unittest\loader.py", line 220, in <listcomp>
    suites = [self.loadTestsFromName(name, module) for name in names]
  File "C:\Users\Tony Bagnall\AppData\Local\Programs\Python\Python39\lib\unittest\loader.py", line 205, in loadTestsFromName
    test = obj()
  File "C:\Code\aeon\aeon\transformations\collection\tests\test_base.py", line 92, in test_inverse_transform
    x2 = d.inverse_transform(x)
  File "C:\Code\aeon\aeon\transformations\collection\base.py", line 198, in inverse_transform
    X_inner = self.preprocess_collection(X)
AttributeError: '_Dummy' object has no attribute 'preprocess_collection'

```

### Versions

_No response_

### Additional contract requirements

- When `skip-inverse-transform` is enabled, `inverse_transform` must return a collection equivalent to its input.
- `inverse_transform` must use the collection-preprocessing behavior supported by the current transformer API and must not depend on the removed legacy preprocessing method.
