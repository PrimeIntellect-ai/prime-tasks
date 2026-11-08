Amber19SB and cmaps
It needs to also [HIDDEN] here to handle `Amber19SB` topologies
https://github.com/ParmEd/ParmEd/blob/252c5ba52ebcd57509feb525d6da9e00f9d1ffe3/parmed/amber/_amberparm.py#L289-L300


## Test code
```python
# Read a GROMACS topology file with Amber19SB ff
com_top = parmed.load_file('topol.top')
com_amb_prm = parmed.amber.AmberParm.from_structure(com_top)
com_amb_prm
```
Happy to open a PR

Mario S.

### Additional contract requirements

- `AmberParm.from_structure` must accept structures containing cmap data, including the reported Amber19SB topology, rather than reject them solely because cmaps are present.
