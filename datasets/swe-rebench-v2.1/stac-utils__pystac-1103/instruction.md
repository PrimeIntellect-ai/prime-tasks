Duplicate `self` link in pystac 1.7.2
```python
import pystac

item = pystac.read_file("https://planetarycomputer.microsoft.com/api/stac/v1/collections/sentinel-2-l2a/items/S2A_MSIL2A_20150704T101006_R022_T35XQA_20210411T133707")
links = item.get_links(rel="self")
print(len(links))

for link in links:
    print(link)
```

That will output

```
2
<Link rel=self target=https://planetarycomputer.microsoft.com/api/stac/v1/collections/sentinel-2-l2a/items/S2A_MSIL2A_20150704T101006_R022_T35XQA_20210411T133707>
<Link rel=self target=https://planetarycomputer.microsoft.com/api/stac/v1/collections/sentinel-2-l2a/items/S2A_MSIL2A_20150704T101006_R022_T35XQA_20210411T133707>
```

for pystac>=1.7.0. On 1.6.1 it outputs just the single `self` link. None of the other links are duplicated, just `self`.

### Additional contract requirements

When an Item is read, it exposes one self link. Other links in the Item document remain present exactly once; correcting the self-link duplication must not remove or duplicate them.
