Deserializing custom default properties from yEd graphML files
When importing a yEd created graphml file with custom properties on the
nodes I found that the default values for boolean properties was always True.

[HIDDEN]

For the defaults, the value of each key is just cast to the appropriate `python_type`
In the case of booleans with value='false' this results in [HIDDEN]  :(


### Expected Behavior
[HIDDEN]

### Steps to Reproduce
Make a yed graphml file with some custom node property of value 'boolean' with default 'false'
import the file using GraphMLReader
The resulting default node property has bool value True.

### Environment
Python version:
Python 3.9.4 (default, Apr  6 2021, 11:23:37)
[Clang 11.0.3 (clang-1103.0.32.62)] on darwin

NetworkX version:
2.5.1

### Additional context
As posted in google discussion group
[https://groups.google.com/g/networkx-discuss/c/XbFTyx-PKqc/m/pD2_WAdYAQAJ](https://groups.google.com/g/networkx-discuss/c/XbFTyx-PKqc/m/pD2_WAdYAQAJ)

### Additional contract requirements

- GraphML node default values must reflect their declared GraphML types. In particular, a boolean default of `false` must result in the boolean value `False`.
