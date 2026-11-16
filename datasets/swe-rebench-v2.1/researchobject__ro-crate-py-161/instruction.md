Support indirect data entity linking from root
Currently we detect data entities only if they are *directly* linked to from the root data entity:

```json
{
    "@id": "./",
    "@type": "Dataset",
    "hasPart": [
        {"@id": "spam"},
        {"@id": "spam/foo.txt"}
    ]
},
{
    "@id": "spam",
    "@type": "Dataset",
    "hasPart": [
        {"@id": "spam/foo.txt"}
    ]
},
{
    "@id": "spam/foo.txt",
    "@type": "File"
}
```

We should also support indirect linking as specified [in the specs](https://www.researchobject.org/ro-crate/1.1/data-entities.html#referencing-files-and-folders-from-the-root-data-entity). In the above example, for instance, we should treat `spam/foo.txt` as a data entity even if it wasn't listed in the root data entity's `hasPart`.
