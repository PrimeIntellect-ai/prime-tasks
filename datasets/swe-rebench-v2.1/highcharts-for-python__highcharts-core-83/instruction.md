xAxis.labels.style isn't applying styles correctly
I am setting [xAxis.labels.style](https://api.highcharts.com/highcharts/xAxis.labels.style) like so in my JS literal options file:
```
xAxis: {
  labels: {
    style: {
      color: "red",
    }
  }
}
```

The outputted JavaScript is:
```
xAxis: {
  labels: {
    style: "{\\'color\\': \\'red\\'}"
  }
}
```

This doesn't happen when setting something else, like [title.style](https://api.highcharts.com/highcharts/title.style).
