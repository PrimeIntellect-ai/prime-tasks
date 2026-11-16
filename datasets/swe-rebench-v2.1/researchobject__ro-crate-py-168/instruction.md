BUG: If Root Data Entity has an arcp:// ID the arcp:// part gets stripped off it
Here's some code to reproduce the error:

```python
from rocrate.rocrate import ROCrate
import json
import os
test_crate = {
  "@context": [
    "https://w3id.org/ro/crate/1.1/context",
    {
      "@vocab": "http://schema.org/"
    }
  ],
  "@graph": [
    {
      "@id": "ro-crate-metadata.json",
      "@type": "CreativeWork",
      "conformsTo": [
        {
          "@id": "https://w3id.org/ro/crate/1.2"
        }
      ],
      "about": {
        "@id": "arcp://name,corpus-of-oz-early-english"
      }


    },
    {"@id": "arcp://name,corpus-of-oz-early-english", "@type": "Dataset"}
  ]}
os.makedirs("test_crate", exist_ok=True)
f = open("test_crate/ro-crate-metadata.json","w")
f.write(json.dumps(test_crate, indent=2))
f.close()
crate = ROCrate("test_crate")
print("ID of root dataset", crate.root_dataset.id) # name,corpus-of-oz-early-english

print("ID of original", test_crate["@graph"][1]["@id"]) # arcp://name,corpus-of-oz-early-english
print("same?", crate.root_dataset.id == test_crate["@graph"][1]["@id"])

```

### Additional contract requirements

- `is_url(string)` is a public function in module `rocrate.utils`. It returns `True` when the string contains a URL scheme component (for example `http`, `https`, `ftp`), and `False` otherwise. Its result deliberately ignores the path component, so a string such as `http://example.com` that has a scheme but no path is still a URL.
