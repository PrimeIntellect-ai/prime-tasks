Support built-in vega themes
See [vega-themes](https://github.com/vega/vega-themes). Themes should be supported via the current theme infrastructure, maybe something like this:
```python
alt.themes.enable('vega.themes.dark')
```
We'll have to think about how to best populate the list of available themes, and how to make this work cleanly with user-specified themes from within Altair.

### Additional contract requirements

- `altair.vegalite.v3.theme.VEGA_THEMES` is a non-empty list of the names of the built-in Vega themes, and every name it contains is registered with the theme registry (`alt.themes`).
- Built-in theme names are the bare vega-themes names, for example `'dark'`; `alt.themes.enable('dark')` must work.
- `alt.themes.enable(theme)` raises an exception when `theme` is not registered.
- Exiting the `with alt.themes.enable(theme):` block restores the previously active theme.
- Themes registered by Altair users through `alt.themes.register` remain available and can be enabled alongside the built-in themes.
