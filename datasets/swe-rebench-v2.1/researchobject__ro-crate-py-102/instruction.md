Entity getitem breaks for null JSON values
Example:

```javascript
    {
      "@id": "sort-and-change-case.ga",
      "@type": [
        "File",
        "SoftwareSourceCode",
        "ComputationalWorkflow"
      ],
      "programmingLanguage": {
        "@id": "#galaxy"
      },
      "name": null
    }
```

```pycon
>>> crate.mainEntity["name"]
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/home/simleo/git/ro-crate-py/rocrate/model/entity.py", line 81, in __getitem__
    deref_values = [self.crate.dereference(_["@id"], _["@id"]) for _ in values]
  File "/home/simleo/git/ro-crate-py/rocrate/model/entity.py", line 81, in <listcomp>
    deref_values = [self.crate.dereference(_["@id"], _["@id"]) for _ in values]
TypeError: 'NoneType' object is not subscriptable
```
