Small tweaks to  catalog
[x] 1. Return slug at every object with slug. For example, Dataset.slug doesn't work but it appears at dataset.to_dict. We talked about removing slug for the model but I'm regretting it after I've played a little bit with the library.

[x] 2. Dataset.to_dict(): remove summary_jsonb.

[x] 3. Rename Catalog to CatalogDataset

[ ] 4. Custom `__repr__` for Variable objet.

![image](https://user-images.githubusercontent.com/1161870/66732255-6bd3fb80-ee5b-11e9-8e2e-975222e564ef.png)

That would be great to include only for Variable object the description fields at the __repr__.

For longer description (bigger than 20 characters  let's add an ellipsis.

<Variable('CRMCYPERC_1a97ab94', 'My cool short description')>
<Variable('CRMCYPERC_1a97ab94', 'My cool long description bla bla bla ...'  )>

### Additional contract requirements

- The dataset catalog model is named `CatalogDataset` and is importable from `cartoframes.data.observatory.dataset` (and re-exported from `cartoframes.data.observatory`).
- `CatalogDataset.get(identifier)` returns the dataset identified by its slug or id, and raises `DiscoveryException` when no dataset matches.
- `CatalogDataset.get_all(filters=None, credentials=None)` returns the datasets that match the supplied filters, wrapped in a `CatalogList`; `credentials` is optional and is used to include purchased datasets.
- `repr(CatalogDataset)` is `"<CatalogDataset('slug')>"` and `str(CatalogDataset)` is `"CatalogDataset({dict})"`, where `{dict}` is the string form of the dataset's raw attribute dictionary.
- `repr(Variable)` is `"<Variable('slug','description')>"`. The effective cutoff for `Variable` descriptions is 30 characters, superseding the earlier 20-character suggestion: descriptions longer than 30 characters are truncated to their first 30 characters followed by `...`.
- `str(Variable)` shows the full variable dictionary as `"Variable({dict})"`.
