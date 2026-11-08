[API] Detector tallies of a single bin are difficult to work with
## Summary of issue
When using a detector w/ a single bin, e.g. one group flux, the bin data in the output file is a single bin. Rather than a proper array, these are floats cast into array form. Indexing doesn't work, but you can get the "values" by converting the arrays to `float`.

## Code for reproducing the issue

[tally_det0.txt](https://github.com/CORE-GATECH-GROUP/serpent-tools/files/2340714/tally_det0.txt)
```
import serpentTools
r = serpentTools.read('tally_det0.txt', 'det')
one = r['one']
one.tallies
# array(8.19E17)
r['two'].tallies
# array([8.19E17, 7.18E17])
r['two'].tallies[0]
# 8.19E17
one.tallies[0]
```
## Actual outcome including console output and error traceback if applicable
This raises an `IndexError`

## Expected outcome
Better way to index tally data of a single point.  Plotting also doesn't work for this as well, as the tally data has no shape, but is of size 1.

Converting these to floats, or an array of a single float, e.g. array([tally]), would help with plotting and slicing down the road.

Labeling as `API-Incompatible` because, depending on the implementation, this could require changes from the user. If this is the case, then this should be included with a release, like 0.6.0

## Versions

* Version  from ``serpentTools.__version__`` `0.5.3`
