The "color" property in MouseEventParams.seriesData for a Line series is not defined, even though it was passed through SeriesApi.setData
**Lightweight Charts Version:** 4.0.0

**Steps/code to reproduce:**

1. Create Line series;
2. Set LineData with color property;
3. Subscribe to corshair move;
4. Hover over the chart;

**Actual behavior:**

MouseEventParams.seriesData doesn't contain 'color' propery

**Expected behavior:**

MouseEventParams.seriesData should contain 'color' property
