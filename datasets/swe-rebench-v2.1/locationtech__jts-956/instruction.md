OffsetCurve does not handle repeated points
The `OffsetCurve` class does not handle linework with repeated points correctly.  This is due to the raw offset curve generator not handling repeated points correctly. [HIDDEN]

### Example
Input with repeated point at `(9 5)`:
```
LINESTRING (4 9, 1 2, 9 5, 9 5, 4 9)
```
The result for offset distance = 1 is:

![image](https://user-images.githubusercontent.com/3529053/220796045-9a12b95d-7858-4026-afe5-7dc51f5aa0d3.png)

if the repeated point is removed, the result is correct:
![image](https://user-images.githubusercontent.com/3529053/220796956-1e485770-7d59-4316-bbac-3d94ee372924.png)

Originally reported in https://github.com/qgis/QGIS/issues/51750.
