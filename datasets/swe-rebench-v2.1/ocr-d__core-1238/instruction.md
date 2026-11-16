parameter decorator: handle preset files as resources
When we drafted the resource handling, one of the use cases was installing preset files, i.e. preconfigured (if incomplete) json parameter sets that have a discernable name and can be used as value for `--parameter|-p` but without the directory path.

That latter part is still missing. So we still need to modify … https://github.com/OCR-D/core/blob/0713e0e1c2fd11242957c3a51c974a1048dba997/ocrd/ocrd/decorators/parameter_option.py#L7-L14 … such that known resource filenames are tried first.

### Additional contract requirements

- `Processor.__init__` in module `ocrd.processor.base` accepts a `resolve_resource` keyword argument. When it is not `None`, the processor resolves the named resource, prints its absolute path, and does not execute the processing workflow.
- `run_cli` in module `ocrd.processor.base` accepts a preset resource name as its `parameter` argument and resolves it via the processor's resource mechanism.
