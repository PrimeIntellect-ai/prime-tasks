Add `len` function for array type
<!-- Answering these questions may help with writing the initial proposal body. Thanks! -->

### Proposal

Currently, it’s not possible to compute the length of array type in Genji

<!--
What is the current status of the proposed behavior? E.g. “Currently, it’s not possible to do X in Genji”.
What is the proposed solution? E.g. “I propose adding SQL syntax Y that does X”.
-->

### Additional contract requirements

- If evaluating the argument expression returns an error, `len` returns that error unchanged. For example, `SELECT len(CAST('\xAF' AS INT))` fails with the error `cannot cast blob as integer`.
