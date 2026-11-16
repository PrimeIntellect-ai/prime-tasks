Plotting error when NaN in the categorical column and there are repetitive colours
- [x] I have checked that this issue has not already been reported.
- [x] I have confirmed this bug exists on the latest version of scanpy.
- [x] (optional) I have confirmed this bug exists on the master branch of scanpy.

---

Related issues: #1975.

### Minimal code sample

The reproducible example below features a few observations but the real-world scenario for this issue is very likely to arise when  there are a lot of categories (larger than the number of colours in the palette) and there is also at least one `NaN` value.

```python
import numpy as np
import pandas as pd
import scanpy as sc

# simulate a categorical column with a missing value
v = pd.Series(np.arange(10).astype(str))
v[0] = np.nan
v = v.astype("category")

ad = sc.AnnData(obs=pd.DataFrame(v, columns=["value"]))
ad.obsm["X_umap"] = np.random.normal(size=(ad.n_obs, 2))

sc.pl.umap(ad, color="value")
# colours are unique

# simulate scenario with non-unique colours
ad.uns['value_colors'][1] = ad.uns['value_colors'][0]

sc.pl.umap(ad, color="value")
# => AttributeError
```

```pytb
---------------------------------------------------------------------------
AttributeError                            Traceback (most recent call last)
<ipython-input-89-b7bdec198ea2> in <module>
----> 1 sc.pl.umap(ad, color="value")

site-packages/scanpy/plotting/_tools/scatterplots.py in umap(adata, **kwargs)
    657     tl.umap
    658     """
--> 659     return embedding(adata, 'umap', **kwargs)
    660
    661

site-packages/scanpy/plotting/_tools/scatterplots.py in embedding(adata, basis, color, gene_symbols, use_raw, sort_order, edges, edges_width, edges_color, neighbors_key, arrows, arrows_kwds, groups, components, layer, projection, scale_factor, color_map, cmap, palette, na_color, na_in_legend, size, frameon, legend_fontsize, legend_fontweight, legend_loc, legend_fontoutline, vmax, vmin, vcenter, norm, add_outline, outline_width, outline_color, ncols, hspace, wspace, title, show, save, ax, return_fig, **kwargs)
    250             groups=groups,
    251         )
--> 252         color_vector, categorical = _color_vector(
    253             adata,
    254             value_to_plot,

[HIDDEN]
   1282             color_vector = color_vector.fillna(to_hex(na_color))
   1283         return color_vector, True

AttributeError: 'Index' object has no attribute 'add_categories'
```

#### Versions

<details>

anndata             0.7.4, 0.7.9

numpy               1.22.2

pandas              1.4.0

scanpy              1.5.1, 1.8.2

</details>


### Workaround

[HIDDEN]

### Additional contract requirements

- Plotting a categorical column with a missing value must complete without error when its palette contains repeated colors.
