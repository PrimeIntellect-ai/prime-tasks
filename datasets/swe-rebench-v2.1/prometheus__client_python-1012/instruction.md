Using None as a label value breaks exposure of all metrics
If a metric is added and provided a label value of `None`, the response generated for scraping raises an AttributeError, preventing any attribute from being scraped, not just the misconfigured one.

Sample code:

```
from prometheus_client import Info, generate_latest

info_metric = Info("metric", "description")
info_metric.info({"label": None})
_ = generate_latest()
```

Output:

```
Traceback (most recent call last):
  File "/home/mol/git/tango/test_metrics.py", line 7, in <module>
    _ = generate_latest()
  File "/home/mol/miniconda3/lib/python3.10/site-packages/prometheus_client/exposition.py", line 282, in generate_latest
    output.append(sample_line(s))
  File "/home/mol/miniconda3/lib/python3.10/site-packages/prometheus_client/exposition.py", line 239, in sample_line
    ['{}="{}"'.format(
  File "/home/mol/miniconda3/lib/python3.10/site-packages/prometheus_client/exposition.py", line 240, in <listcomp>
    k, v.replace('\\', r'\\').replace('\n', r'\n').replace('"', r'\"'))
AttributeError: ("'NoneType' object has no attribute 'replace'", Metric(metric, description, info, , [Sample(name='metric_info', labels={'label': None}, value=1.0, timestamp=None, exemplar=None)]))
```

The misconfigured metric not getting exposed is fine -- `None` is not a valid label value. But the other metrics not getting exposed either is painful. [HIDDEN]

### Additional contract requirements

Handling a `None` label value must not prevent other valid metrics from being exposed; the metric with the bad value need not itself be exposed.
