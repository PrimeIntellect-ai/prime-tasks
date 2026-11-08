Rounding drawnPath's data
For both, the current level of decimals precision is certainly not needed, and rather unnecessary noise.
Reminder : `drawingWidth` default is **4px**.
See :
![screenshot from 2018-02-26 11-44-04](https://user-images.githubusercontent.com/1420189/36666324-7e04201e-1aea-11e8-9433-a3cb3b9701f3.png)

### Additional contract requirements

- Round coordinates in SVG path strings and in the `drawnPath` callback's `points` to one decimal place.
