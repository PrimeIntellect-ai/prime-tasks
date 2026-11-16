Don't emit LF after Outdent, causes wrong token positions
Currently, when ScannerTokens.nextToken works with `prevPos` pointing to last token, and `currPos` referring to a whitespace/comment token ("trivial"), it considers range between `prevPos` and `nextPos` (next non-nontrivial token).

If it determines that an outdent needs to be produced here, the position of the outdent refers to the last newline, in order to include all possible comments.

However, it also produces an LF token after that, and that token uses a position of the **first** newline in the range instead (see #3780), leading to presumably empty trees covering non-empty token ranges.
