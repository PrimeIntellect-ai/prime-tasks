[BUG] Incorrect column pointer initialization in RowColumnWiseSorted2dArrayBinarySearch
### Description

-  I've identified a bug in the `RowColumnWiseSorted2dArrayBinarySearch.java` implementation.
[HIDDEN]
- This causes the algorithm's starting point to be incorrect for any matrix that is not square.
- The problematic line is:
```java
// in src/main/java/com/thealgorithms/searches/RowColumnWiseSorted2dArrayBinarySearch.java

[HIDDEN]
```

### Steps to reproduce

- The bug can be reproduced with any non-square matrix where the number of rows and columns are different.
- For example, with a 2x4 matrix:
```java
   1 int[][] matrix = {
   2     {10, 20, 30, 40},
   3     {15, 25, 35, 45}
   4 };
```
- With the current code, matrix.length is 2, so colPointer is initialized to 1.
- The search incorrectly starts at matrix[0][1] (value 20) instead of the top-right corner matrix[0][3] (value 40).

### Excepted behavior

- [HIDDEN] The correct initialization should be:
[HIDDEN]

### Screenshots

_No response_

### Additional context

I would like to submit a Pull Request to fix this initialization issue.

### Additional contract requirements

- Search should correctly locate present targets in non-square matrices whose rows and columns are sorted.
