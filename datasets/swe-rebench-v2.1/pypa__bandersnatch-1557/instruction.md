Ensure bandersnatch implements pep700 fields
https://peps.python.org/pep-0700/

- The api-version must specify version 1.1 or later.
- A new versions key is added at the top level.
- Two new “file information” keys, size and upload-time, are added to the files data.

Keys (at any level) with a leading underscore are reserved as private for index server use. No future standard will assign a meaning to any such key.

### Additional contract requirements

- The JSON document must preserve this key order: top-level `files`, `meta`, `name`, `versions`; each file entry `filename`, `hashes`, `requires-python`, `size`, `upload-time`, `url`, `yanked`; and `meta` entries `api-version`, `_last-serial`.
- When the JSON is pretty-printed, use four spaces per indentation level; otherwise include a space after each comma and colon.
