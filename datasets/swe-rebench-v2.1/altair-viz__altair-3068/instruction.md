JSON to Chart failure in v5.0.0
As part of a larger application, we're moving chart content around in JSON format via `Chart.to_json` and `Chart.from_json`. However, I'm encountering an error after updating to Altair v5.0.0. An example that used to work previously - based on the layered chart in https://altair-viz.github.io/altair-tutorial/notebooks/09-Geographic-plots.html

```python
import altair as alt
from vega_datasets import data

states = alt.topo_feature(data.us_10m.url, feature='states')
airports = data.airports()

background = alt.Chart(states).mark_geoshape(
    fill='lightgray',
    stroke='white'
).project('albersUsa').properties(
    width=500,
    height=300
)

points = alt.Chart(airports).mark_circle().encode(
    longitude='longitude:Q',
    latitude='latitude:Q',
    size=alt.value(10),
    tooltip='name'
)

chart = background + points

json = chart.to_json()
chart = alt.Chart.from_json(json)
```

In v4.2.2 this runs without any errors. In v5.0.0 this results in

```
Traceback (most recent call last):
  File "altair_scratchpad.py", line 25, in <module>
    chart = alt.Chart.from_json(json)
  File "C:\Users\romesh\miniconda3\envs\atomica38\lib\site-packages\altair\utils\schemapi.py", line 914, in from_json
    return cls.from_dict(dct, validate=validate)
  File "C:\Users\romesh\miniconda3\envs\atomica38\lib\site-packages\altair\vegalite\v5\api.py", line 2497, in from_dict
    return class_.from_dict(dct, validate=validate)  # type: ignore[attr-defined]
  File "C:\Users\romesh\miniconda3\envs\atomica38\lib\site-packages\altair\utils\schemapi.py", line 893, in from_dict
    return converter.from_dict(dct, cls)
  File "C:\Users\romesh\miniconda3\envs\atomica38\lib\site-packages\altair\utils\schemapi.py", line 1058, in from_dict
    return cls(**kwds)
  File "C:\Users\romesh\miniconda3\envs\atomica38\lib\site-packages\altair\vegalite\v5\api.py", line 2982, in __init__
    combined_dict, self.layer = _remove_layer_props(self, self.layer, layer_props)
  File "C:\Users\romesh\miniconda3\envs\atomica38\lib\site-packages\altair\vegalite\v5\api.py", line 3393, in _remove_layer_props
[HIDDEN]:
  File "C:\Users\romesh\miniconda3\envs\atomica38\lib\site-packages\altair\vegalite\v5\api.py", line 3393, in <genexpr>
[HIDDEN]
  File "C:\Users\romesh\miniconda3\envs\atomica38\lib\site-packages\altair\utils\schemapi.py", line 711, in __getitem__
    return self._kwds[item]
KeyError: 'height'
```
