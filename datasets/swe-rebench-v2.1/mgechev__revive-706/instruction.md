Does it make sense to check the duplicate struct tag name?
**Is your feature request related to a problem? Please describe.**
Duplicate tag name should make no sense in the same struct and most of
cases should be mistaken, so I think we can check the struct tag.

**Describe the solution you'd like**

Check whether has the duplicate struct tag key or not

**Describe alternatives you've considered**
No

**Additional context**
No

### Additional contract requirements

- Detect duplicate tag names on different fields of the same struct independently within each of these tag namespaces: `json`, `xml`, `bson`, `yaml`, and `protobuf`. A name repeated under different tag keys is not a duplicate. For `protobuf` tags, use the value of the `name` option as the tag name; for the other formats, use the name before any comma-separated options.
- Report a duplicate with the diagnostic `duplicate tag name: '<tag name>'`, for example `duplicate tag name: 'defaultInt2'`, on the line of the later field that repeats the name.
- A tag whose name is `-` or empty is not a name and is never reported as a duplicate.
