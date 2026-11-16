Case recorder files can contain Python objects whose classes are not importable
### Description

If a user makes use of some external packages like VSP wrappers, the case recorder file will have pickled objects from that package. If that case recorder file is opened in a Python environment which does not have that package installed, there will be an exception since the class of that object will not be available to be imported.

Need to handle the reading of case recorder files more intelligently so that the reading doesn't completely fail. Should read in what is doable and set to empty what is not. Give the user a warning about what happened.

### Example

The example that brought out this issue was a user doing an Aviary run using OpenVSP and then sending the case recorder file to another user who did not have OpenVSP installed.

The test created as part of the PR that fixes this bug will give an example of the bug.

### OpenMDAO Version

3.31.2-dev

### Relevant environment information

NA

### Additional contract requirements

- When the unavailable module is `mymodule`, emit a `RuntimeWarning` with the exact message `While reading system options from case recorder, the following errors occurred: No module named 'mymodule'`.
