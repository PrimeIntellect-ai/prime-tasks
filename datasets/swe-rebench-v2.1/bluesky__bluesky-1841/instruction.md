set_run_key_wrapper breaks if baseline is present
<!--- Provide a general summary of the issue in the Title above -->
If you have a baseline preprocessor, using `set_run_key_wrapper` on a plan will lead to an error, due to the baseline not being aware of the run key


## Current Behavior
```python
In [41]: RE.preprocessors
Out[41]:
[SupplementalData(baseline=[Manipulator(prefix='', name='manipulator', settle_time=0.0, timeout=None, egu='', limits=(0, 0), source='computed', read_attrs=['sx', 'sx.readback', 'sx.setpoint', 'sy', 'sy.readback', 'sy.setpoint', 'sz', 'sz.readback', 'sz.setpoint', 'sr', 'sr.readback', 'sr.setpoint', 'x', 'y', 'z', 'r'], configuration_attrs=['sx', 'sy', 'sz', 'sr'], concurrent=True), SoftPositioner(name='eslit', settle_time=0.0, timeout=None, egu='', limits=(0, 0), source='computed'), SoftPositioner(name='i0upAu', settle_time=0.0, timeout=None, egu='', limits=(0, 0), source='computed'), SoftPositioner(name='tesz', settle_time=0.0, timeout=None, egu='', limits=(0, 0), source='computed')], monitors=[], flyers=[]),
 SupplementalData(baseline=[], monitors=[], flyers=[])]

In [42]: RE(set_run_key_wrapper(count([tes, ucal_i400], 5), "test_run_key"))


Transient Scan ID: 7     Time: 2022-06-30 12:04:46
Persistent Unique Scan ID: '4d35d081-e899-46ae-ae4d-520bd3561499'



An exception has occurred, use '%tb verbose' to see the full traceback.
KeyError: None

The above exception was the direct cause of the following exception:
IllegalMessageSequence: Cannot bundle readings without an open run. That is, 'create' must be preceded by 'open_run'.

See /home/ctitus/.cache/bluesky/log/bluesky.log for the full traceback.

In [43]: %tb verbose
---------------------------------------------------------------------------
KeyError                                  Traceback (most recent call last)
File ~/miniconda3/envs/2022-2.3-py39-tiled/lib/python3.9/site-packages/bluesky/run_engine.py:1807, in RunEngine._create(self=<bluesky.run_engine.RunEngine object>, msg=Msg('create', obj=None, args=(), kwargs={'name': 'baseline'}, run=None))
   1806 try:
-> 1807     current_run = self._run_bundlers[run_key]
        run_key = None
        self._run_bundlers = {}
        self = <bluesky.run_engine.RunEngine object at 0x7f1fdae11eb0>
   1808 except KeyError as ke:

KeyError: None
```
## Possible Solution
<!--- Not obligatory, but suggest a fix/reason for the bug, -->
<!--- or ideas how to implement the addition or change -->
Somehow, preprocessors need to be made aware of the run key, or set_run_key_wrapper needs to have a different mechanism (the new run key gets set as the default?)

## Steps to Reproduce (for bugs)
<!--- Provide a link to a live example, or an unambiguous set of steps to -->
<!--- reproduce this bug. Include code to reproduce, if relevant -->
1. Register a baseline signal
2. Run a plan that has been wrapped with set_run_key_wrapper
3. Profit??
