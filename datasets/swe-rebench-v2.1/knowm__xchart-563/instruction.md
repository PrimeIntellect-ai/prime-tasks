Chart has one label too many when specifying setXAxisMaxLabelCount
`setXAxisMaxLabelCount` is honored but not precisely. It seems like whatever you specify as the label count, XChart takes this and adds one more.

e.g.
```
    java.util.List<String> xData = Arrays.asList("one", "two", "three", "four", "five", "six");
    java.util.List<Double> yData = Arrays.asList(2.0, 1.0, 0.0, -1.0, 2.0, 4.0);

    CategoryChart chart = new CategoryChart(800, 600);
    chart.addSeries("first", xData, yData);
    chart.getStyler().setXAxisMaxLabelCount(3);

    BitmapEncoder.saveBitmap(chart, "/tmp/actual.png", BitmapEncoder.BitmapFormat.PNG);
```
yields
![actual](https://user-images.githubusercontent.com/762437/106948406-f2d17500-672b-11eb-8726-1a0ec4a68a31.png)
