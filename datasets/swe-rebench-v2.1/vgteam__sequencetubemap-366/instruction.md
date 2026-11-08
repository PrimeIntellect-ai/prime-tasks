Make BED region download lazy to alow thousands of premade BED regions
Right now, when we download a BED file from a URL, we immediately try to download some metadata about each region.

We need to make this lazy instead, so that we only try to download anything about a region when it is actually accessed.

This will be required to support BED files with thousands of regions, which the Lancet team needs.
