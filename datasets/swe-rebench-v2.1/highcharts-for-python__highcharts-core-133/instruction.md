Blank charts after 1.4.0 update when PieSeries is included
After upgrading `highcharts-core` from v1.3.7 to v1.4.0, my charts now load as blank. After some further investigation, I can get the charts to load properly when I disable the pie charts (I have 2 bar charts, 2 pie charts, and a map chart).

Were there some non-backward-compatible changes made to pie charts in v1.4.0? (Still broken on v1.5.0)

Here's the relevant DOM output with only one pie chart enabled:
```
<div id="contracts_category_breakdown" class="dashboard-chart"></div>

<script>
        Highcharts.setOptions({
  colors: ['#66BA9D',
'#FF8D9A',
'#8980FF',
'#FFBC74',
'#5F5E5E',
'#7BB3FF'],
  credits: {
  enabled: false
},
  exporting: {
  buttons: {
  'contextButton': {
  x: 5,
  y: -10
}
}
},
  lang: {
  thousandsSep: ','
},
  navigation: {
  menuItemStyle: {'color': '#5f5e5e', 'fontFamily': 'Roboto', 'fontSize': '12px'}
},
  plotOptions: {
  bar: {
  pointPadding: 0,
  type: 'bar'
},
  column: {
  colorByPoint: true,
  pointPadding: 0,
  type: 'column'
},
  pie: {
  dataLabels: {
  enabled: false
},
  showInLegend: true,
  type: 'pie'
},
  series: {
  dataSorting: {
  enabled: true
},
  type: 'series'
}
},
  title: {
  align: 'left',
  style: {'color': '#000000', 'fontFamily': 'Roboto', 'fontSize': '16px', 'fontWeight': '500'},
  text: 'Chart title'
},
  xAxis: {
  lineWidth: 0,
  labels: {
  style: {'color': '#5f5e5e', 'fontFamily': 'Roboto', 'fontSize': '12px'}
}
},
  yAxis: {
  title: {
  text: null
}
}
});
        document.addEventListener('DOMContentLoaded', function() {
Highcharts.chart('contracts_category_breakdown',
{
  exporting: {
  buttons: {
  'contextButton': {
  menuItems: ['viewFullscreen',
'printChart']
}
}
},
  legend: {
  align: 'right',
  enabled: true,
  itemStyle: {'color': '#5f5e5e', 'fontFamily': 'Roboto', 'fontSize': '12px'},
  labelFormat: '{name} {percentage:.1f}%',
  layout: 'vertical',
  verticalAlign: 'bottom'
},
  plotOptions: {
  pie: {
  allowPointSelect: true,
  cursor: 'pointer',
  dataLabels: {
  enabled: false
},
  showInLegend: true,
  type: 'pie'
},
  series: {
  dataSorting: {
  enabled: false
},
  type: 'series'
}
},
  series: [{
  data: [['Electricity',
154],
['Natural Gas',
101]],
  type: 'pie'
}],
  title: {
  text: 'Contracts Category Breakdown'
},
  tooltip: {
  format: {point.name}: {point.y},
  style: {'color': '#5F5E5E', 'fontFamily': 'Roboto', 'fontSize': '12px', 'fontWeight': '700'}
}
},
);
});
</script>
```

### Additional contract requirements

- The public function `is_js_object(as_str: str, careful_validation: bool = False) -> bool` in module `highcharts_core.js_literal_functions` returns `True` when the given string represents a JavaScript object literal, and `False` otherwise.
- A string that merely starts with `{` and contains a colon, such as `'{point.name}: {point.y}'`, is not an object literal and returns `False`.
- When `careful_validation` is `True`, a stricter syntactic validation is applied, so strings that are not object literals (for example a constructor call such as `new Date()`) return `False`.



- JavaScript object-literal detection must distinguish object literals from text that cannot be parsed as an object literal; malformed brace-delimited text is not an object literal. This applies in the default validation mode as well as in careful validation mode.
- A tooltip format string such as `{point.name}: {point.y}` is text, not an object literal, and must remain a string when a tooltip is parsed and serialized.
- Careful validation must reject non-object expressions such as `new Date()`.
