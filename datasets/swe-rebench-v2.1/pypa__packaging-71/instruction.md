Marker support for `platform.python_implementation` lost
When Setuptools adopted Packaging 16.x for the marker implementation, it [lost support for](https://bitbucket.org/pypa/setuptools/issues/503/) the deprecated `platform.python_implementation` marker, which prevents packages using that deprecated marker from installing under Setuptools 20.2+.

@s-t-e-v-e-n-k Can you develop a patch to support this legacy expectation?
