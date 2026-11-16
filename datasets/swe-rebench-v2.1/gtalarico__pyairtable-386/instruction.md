There should be a way to always set `return_fields_by_field_id` to `True` on all supported calls.
Is this already supported? If so, I have not been able to find it. If not, then it would be a welcome feature addition!

### Additional contract requirements

An `Api` instance can be configured with `use_field_ids=True`. For supported calls that return records, this makes field IDs the default in returned record fields, without needing to set the option on each call. A caller may still override this default for an individual call.
