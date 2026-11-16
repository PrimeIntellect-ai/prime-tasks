[BUG] Backtracking > Floodfill : Code goes in infinite calling loop when same color is passed in newColor and oldColor
### Description

Backtracking > Floodfill
Hi,
When same int color  is passed as both newColor and oldColor parameter, code goes to infinite calling loop in recursion and stack overflow exception occurs causing program to shut down.


My observation is , this case is not handled properly in base cases and
I would really like contributing to resolve this issue.
Here is my PR , resolving this issue : https://github.com/TheAlgorithms/Java/pull/4359
Thanks.


### Steps to reproduce

Pass same color as newColor and oldColor as example while calling FloodFill.floodFill method.

```
Testcase :
@Test
    void testForSameNewAndOldColor() {
        int[][] image = {
                {1, 1, 2},
                {1, 0, 0},
                {1, 1, 1},
        };

        int[][] expected = {
                {1, 1, 2},
                {1, 0, 0},
                {1, 1, 1},
        };

        FloodFill.floodFill(image, 0, 0, 1, 1); // newColor = oldColor = 1
        assertArrayEquals(expected, image);
    }
```

This testcase produce error as below :
```
java.lang.StackOverflowError
	at com.thealgorithms.backtracking.FloodFill.floodFill(FloodFill.java:49)
	at com.thealgorithms.backtracking.FloodFill.floodFill(FloodFill.java:49)
	at com.thealgorithms.backtracking.FloodFill.floodFill(FloodFill.java:50)
	at com.thealgorithms.backtracking.FloodFill.floodFill(FloodFill.java:49)
	at com.thealgorithms.backtracking.FloodFill.floodFill(FloodFill.java:50)
	...
```


### Excepted behavior

As both new and old color are same it should not change anything in given image and return from the function without any exception or issue.

### Screenshots

_No response_

### Additional context

_No response_
