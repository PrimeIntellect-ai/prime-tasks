Add top identifier count analysis
It is already possible to see the top identifier selectors, but it would be nice to have direct access to the top identifier count directly instead of having to get that from another metric.

### Additional contract requirements

Expose the highest identifier count for the analyzed selectors at `selectors.identifiers.max.count` in the analysis results. The value is the number of identifier parts in the selector with the greatest identifier count.
