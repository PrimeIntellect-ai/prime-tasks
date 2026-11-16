feature: increase user-configurable CBOR limit for MaxArrayElements and MaxMapPairs
**Is your feature request related to a problem? Please describe.**

Current limit of DecOptions.MaxArrayElements and DecOptions.MaxMapPairs is:
* default limit = 131072
* max limit user can set =  134217728

At least one project already set limits to the max allowed.  Also, schema-less binary formats like CBOR will be used in large systems and for use cases not initially anticipated.

**Describe the solution you'd like**

Continue to keep default limits reasonably safe & usable, only increase user-configurable max.

Increase limit of DecOptions.MaxArrayElements and DecOptions.MaxMapPairs to:
* default limit = 131072 (unchanged)
* max limit user can set =  2147483647 (0x7FFFFFFF)

**Describe alternatives you've considered**

* Ignore this until a user requests an increase.
* Other (smaller) values were too arbitrary compared to the largest positive signed 32-bit int.
