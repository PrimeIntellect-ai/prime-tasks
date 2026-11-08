Add method to include additional contexts at the top level
Right now, it is possible to add additional terms from other contexts to the top level contexts through the attached `Metadata` instance, using the `extra_terms` dictionary:

```python
a_crate = ROCrate(gen_preview=False)
a_crate.metadata.extra_terms.update(
    {
        "sha256": "https://w3id.org/ro/terms/workflow-run#sha256"
    }
)
```

which leads to

```json
{
    "@context": [
        "https://w3id.org/ro/crate/1.1/context",
        {
            "sha256": "https://w3id.org/ro/terms/workflow-run#sha256"
        }
    ],
    "@graph": [
```

but there is no method nor provision in the current implementation to add additional contexts, in order to get something like:

```json
{
    "@context": [
        "https://w3id.org/ro/crate/1.1/context",
        "https://w3id.org/ro/terms/workflow-run"
    ],
    "@graph": [
```

Could you add such method, please?

### Additional contract requirements

- Additional context URLs can be added through the crate's `metadata` object by appending them to its `extra_contexts` list (the same object that `extra_terms` lives on).
- After a URL is added, the `@context` of the generated top-level JSON-LD document (`crate.metadata.generate()`) includes that URL alongside the RO-Crate profile context.
- Adding an additional context does not prevent `extra_terms` mappings from appearing in the generated `@context`.
