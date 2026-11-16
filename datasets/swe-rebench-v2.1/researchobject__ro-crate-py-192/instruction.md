Allow entities to be passed in as `properties` values when initialising an entity
Example demonstrating the issue:
```python
from rocrate.model import ContextEntity, Person
from rocrate.rocrate import ROCrate

crate = ROCrate()

alice = crate.add(
    Person(
        crate,
        "https://orcid.org/0000-0000-0000-0000",
        properties={"name": "Alice Doe", "affiliation": "University of Flatland"},
    )
)
bob = crate.add(
    Person(
        crate,
        "https://orcid.org/0000-0000-0000-0001",
        properties={"name": "Bob Doe", "affiliation": "University of Flatland"},
    )
)

data = crate.add_file(
    "data.csv",
    properties={
        "name": "Data file",
        "encodingFormat": "text/csv",
        "author": [alice, bob],
    },
)

crate.write("out_crate")
```
Running this yields an error:
```
Traceback (most recent call last):
  File "/home/eli/roc/testing/crate.py", line 30, in <module>
    crate.write("crate_out")
  File "/home/eli/roc/testing/.venv-zenodo/lib/python3.12/site-packages/rocrate/rocrate.py", line 453, in write
    writable_entity.write(base_path)
  File "/home/eli/roc/testing/.venv-zenodo/lib/python3.12/site-packages/rocrate/model/metadata.py", line 80, in write
    json.dump(as_jsonld, outfile, indent=4, sort_keys=True)
. . .
TypeError: Object of type Person is not JSON serializable
```

This is because including the author entities in `properties` isn't supported. Instead I would have to use
```python
data = crate.add_file(
    "data.csv",
    properties={
        "name": "Data file",
        "encodingFormat": "text/csv",
    },
)
data["author"] = [alice, bob]
```

In my opinion this is a less intuitive way of doing things, and it's not straightforward for the user to understand why the second method works and the first one doesn't.

Solution

[HIDDEN]

### Additional contract requirements

- Entity instances supplied as `properties` values, including within lists, must behave like the same values assigned after construction: references must be linked to the crate and remain usable when the crate is written and loaded.
