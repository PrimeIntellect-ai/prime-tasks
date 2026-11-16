Allow to attach partials to a crate?
Hi,

For Autosubmit, since the workflow configuration doesn't contain the information needed for RO-Crate, I [used](https://earth.bsc.es/gitlab/es/autosubmit/-/merge_requests/317) the exact same approach from [COMPSs](https://github.com/bsc-wdc/compss/blob/9e79542eef60afa9e288e7246e697bd7ac42db08/compss/runtime/scripts/system/provenance/generate_COMPSs_RO-Crate.py) and asked users to provide a YAML file with authors & license.

Then I create the objects and attach/add to the RO-Crate-py object.

The implementation in Autosubmit is similar, but not identical to COMPSs. Other workflow managers with similar need may craft yet another way of doing the same.

It would be nice if there was a way to load RO-Crate-py entities directly from a dictionary/YAML data. Something like

```py

from rocrate.entities.person import Person

crate = ROCrate()

with open('') as f:
  yaml_content = parser.safe_load(f)

for author in yaml_content['authors']:
  crate.add(Person.load_from_dict(author)
```

Not sure how to validate the format of the entities... maybe instead of YAML receive JSON-LD directly, or provide a tool/script to read SPARQL+SHACL, etc.?

Cheers
Bruno

### Additional contract requirements

The `ROCrate` class must provide the following public methods for adding and
updating entities directly from JSON-LD dictionaries:

- `ROCrate.add_jsonld(jsonld)`: adds a new contextual entity from a non-empty
  JSON-LD dictionary that contains the `@id` and `@type` keys. It raises
  `ValueError` if the dictionary is empty or `None`, if `@id` or `@type` is
  missing, or if an entity with the given `@id` already exists in the crate.
- `ROCrate.update_jsonld(jsonld)`: updates the properties of an existing entity
  identified by `@id` from a non-empty JSON-LD dictionary. Keys that start with
  `@`, other than `@id`, are ignored for the update. It raises `ValueError` if
  the dictionary is empty or `None`, if `@id` is missing, or if no entity with
  the given `@id` exists in the crate.
- `ROCrate.add_or_update_jsonld(jsonld)`: adds a new entity when the given `@id`
  is not already present in the crate, and updates the existing entity when it
  is. It raises `ValueError` if the dictionary is empty or `None` or if `@id` is
  missing.

The `ValueError` message must contain the substring `non-empty JSON-LD` when the
input is empty, `None`, or missing a required identifier; it must contain `@type`
when `add_jsonld` is missing that key; it must contain `already exists` when
`add_jsonld` receives an identifier that is already in the crate; and it must
contain `does not exist` when `update_jsonld` receives an unknown identifier.
