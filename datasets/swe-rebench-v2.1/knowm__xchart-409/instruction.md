Cannot change annotation position in category chart
Hi everyone,
I'm trying to change position of annotation and haven't possibility to do it.
Also it would be great to introduce displaying total value for this type of chart.

The problem with position also exists for tooltips.
See attached screenshot
![annotation_bug](https://user-images.githubusercontent.com/8298687/72525767-f6226600-3875-11ea-907b-be5f2ddd0ff2.png)

Important **CategoryChart** example settings:
Stacked = true
HasAnnotations = true

for tooltips:
ToolTipsEnabled = true
ToolTipsAlwaysVisible = true

### Additional contract requirements

- For a stacked `CategoryChart` with value annotations enabled (`Styler.setStacked(true)` and `Styler.setHasAnnotations(true)`), the user must be able to change where the value annotations are placed inside the bars, using `Styler.setAnnotationsPosition(float)` with a value between 0 and 1. Changing this value must change where the annotations are drawn. The current value is returned by `Styler.getAnnotationsPosition()`.
- For a stacked `CategoryChart`, the user must be able to show the total value of each stack, using `Styler.setShowTotalAnnotations(boolean)`. The option is off by default. When it is on, the total value of each stack is drawn in the rendered chart. The current setting is returned by `Styler.isShowTotalAnnotations()`.
