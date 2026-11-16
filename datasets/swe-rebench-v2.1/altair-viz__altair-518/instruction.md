Remove default width/height from Chart?
Having defaults causes issues with faceted plots (which become comically large) and with things like ``rangeStep``, which are ignored if ``width`` and ``height`` are set (see #481).

I would propose removing these defaults.

The disadvantage is that straightforward charts end up being smaller than is perhaps ideal for display in the notebook.

### Additional contract requirements

- For a basic Vega-Lite v2 chart, `to_dict()` must include `config.view.width` equal to `400` and `config.view.height` equal to `300`.
