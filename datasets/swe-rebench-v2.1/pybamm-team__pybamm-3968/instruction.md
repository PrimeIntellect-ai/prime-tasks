PyBaMM import error - Cannot run anything (import broken due to `pybtex`)
### Discussed in https://github.com/pybamm-team/PyBaMM/discussions/3928

<div type='discussions-op-text'>

<sup>Originally posted by **abhishek-appana** March 25, 2024</sup>
Hello,

I am running Python 3.11.8 and installed PyBaMM 24.1 using pip on a Windows system. Earlier I was using Python 3.10 and everything was fine. But I am getting the below error after upgrading Python.

When I run `import pybamm`, it gives me the error:

ModuleNotFoundError: Optional dependency pybtex.database is not available. See https://docs.pybamm.org/en/latest/source/user_guide/installation/index.html#optional-dependencies for more details.

I tried installing pybamm using `pip install pybamm[all]`. I was still getting this error. How do I resolve this?</div>

<hr>

I think that this is a valid bug and it is still failing, and `import pybamm` should work without installing `pybamm[all]`. It can be noticed in the logs here: https://github.com/pybamm-team/PyBaMM/actions/runs/8461852686/job/23182296194, so I've converted this discussion to an issue instead (cc: @Saransh-cpp @arjxn-py).

Perhaps this isn't being properly checked through #3892, @lorenzofavaro?
