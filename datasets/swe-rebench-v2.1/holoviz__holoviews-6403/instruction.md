Attach ScaleBar to subcoordinate axis
Allow adding scale bars to individual subplot/subcoordinate_y ranges. The current implementation only allows for a scale bar to be positioned relative to the entire plot. This depends on progress in Bokeh: https://github.com/bokeh/bokeh/issues/13921

A possible API might be to use a new arg; something like `scalebar_level="subcoordinate_y"`

<details> <summary> Code </summary>

```python
import holoviews as hv
import numpy as np
hv.extension("bokeh")

# scalebar_level="subcoordinate_y")

common_opts = dict(subcoordinate_y=True, scalebar=True, scalebar_range='y', scalebar_unit=('cm', 'm'),)

c1 = hv.Curve(np.random.rand(1000), label='c1').opts(color='lightblue',  scalebar_location="left", scalebar_opts={'bar_length':.1, 'background_fill_alpha': .2, 'bar_line_color':'darkblue'}, **common_opts)
c2 = hv.Curve(np.random.rand(1000), label='c2').opts(color='indianred', scalebar_location="bottom_right", scalebar_opts={'bar_length':.1, 'background_fill_alpha': .2, 'bar_line_color':'darkred'}, **common_opts)
c3 = hv.Curve(np.random.rand(1000), label='c3').opts(color='plum', scalebar_location="top_left", scalebar_opts={'bar_length':.1, 'background_fill_alpha': .2, 'bar_line_color':'purple'}, **common_opts)
c4 = hv.Curve(np.random.rand(1000), label='c4').opts(color='palegreen', scalebar_location="right", scalebar_opts={'bar_length':.1, 'background_fill_alpha': .2, 'bar_line_color':'darkgreen'}, **common_opts)

curves = hv.Overlay(c1 * c2 * c3 * c4).opts(show_legend=False)
curves.opts(width=800, height=600)
```

</details>


Arrows indicate where the scale bars should be after applying to subcoordinate level:

![image](https://github.com/holoviz/holoviews/assets/6613202/84efb1f7-4424-43be-adeb-901825181270)

### Additional contract requirements

- Scale bars on individual subcoordinate ranges are enabled through the existing
  `scalebar=True` option combined with `subcoordinate_y=True` on an element; no new
  option is required.
- Each element drawn with `subcoordinate_y=True` and `scalebar=True` gets its own scale
  bar, and that scale bar is linked to that element's own subcoordinate y-range rather
  than the plot's overall y-range.
