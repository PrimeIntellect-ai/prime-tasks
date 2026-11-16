HRA regression when rasterizing spatial criteria
A [user on the forums](https://community.naturalcapitalproject.org/t/habitat-risk-assessment-problems-with-risk-calculation-and-outputs/3122/15) noticed a difference in how spatial criteria were being represented between InVEST 3.9 (former HRA) and InVEST 3.12 (the new HRA implementation), specifically around how input vectors are being rasterized.

After digging into this for a while, it appears that the InVEST 3.9 implementation makes the following distinction that I missed when rewriting HRA:
* Habitat and stressor vectors are rasterized with `ALL_TOUCHED=TRUE`
* Spatial criteria vectors are rasterized with `ALL_TOUGHED=FALSE`

The current HRA does not make this distinction, but probably should, at least for backwards compatibility.

For what it's worth, I could not find this distinction in the InVEST 3.3.0 HRA.
