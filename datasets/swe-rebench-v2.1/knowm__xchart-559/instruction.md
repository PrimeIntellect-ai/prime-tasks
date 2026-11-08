Line annotations out of chart area
Hi,
it would be great to have the line annotations just inside the chart area, not on the whole panel.

![annotation](https://user-images.githubusercontent.com/19358486/106374460-c7afe580-6327-11eb-82ef-9069d8690529.png)

### Additional contract requirements

- `org.knowm.xchart.AnnotationLine` provides the public constructor `AnnotationLine(double value, boolean isVertical, boolean isValueInScreenSpace)`. `isVertical` selects a vertical line when `true` and a horizontal line when `false`.
- `value` is the line's coordinate in chart space, or a screen-space (pixel) coordinate when `isValueInScreenSpace` is `true`. A screen-space horizontal line is placed `value` pixels above the bottom edge of the chart, and a screen-space vertical line is placed `value` pixels from the left edge.
- `AnnotationLine` exposes the rendered annotation's bounding rectangle in screen (pixel) coordinates through its public `getBounds()` method.
