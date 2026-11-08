Bug: Won't load a crate with hasPart reference to a RepositoryCollection.
Loading the below test data gives an error:

```
File "/Users/pt/working/ro-crate-py/test.py", line 3, in <module>
    crate = ROCrate("haspart")
  File "/Users/pt/rocrate/lib/python3.9/site-packages/rocrate/rocrate.py", line 92, in __init__
    self.build_crate(entities, source_path, gen_preview)
  File "/Users/pt/rocrate/lib/python3.9/site-packages/rocrate/rocrate.py", line 227, in build_crate
    self.add(instance)
UnboundLocalError: local variable 'instance' referenced before assignment

```

I would expect to be able to load anything with a flat JSON-LD structure even if it's not schema.org compliant.


Here's the offending ro-crate-metadata.json

```json
{
  "@context": [
    "https://w3id.org/ro/crate/1.1/context",
    {
      "@vocab": "http://schema.org/"
    },
    {
      "@base": null
    }
  ],
  "@graph": [
    {
      "@id": "#collection",
      "@type": "RepositoryCollection ",
      "name": "Test collection"
    },
    {
      "@id": "./",
      "@type": "Dataset",
      "hasFile": [],
      "hasPart": [{"@id": "#collection"}],
      "name": "testing hasPart"
    },
    {
      "@id": "ro-crate-metadata.json",
      "@type": "CreativeWork",
      "about": {
        "@id": "./"
      },
      "identifier": "ro-crate-metadata.json"
    }
  ]
}
```
