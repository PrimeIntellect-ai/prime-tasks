Add South America extract to results.openaddress.io
With the new Brazil data adding millions++ of addresses it'd be nice to download that without resorting to the `global` option.

http://results.openaddresses.io

### Additional contract requirements

- Add a public function `is_south_america(result)` in the module `openaddr/ci/collect.py`. It returns `True` when the result's source corresponds to a South American country and `False` otherwise. The South American ISO 3166-1 alpha-2 country codes are `ar`, `bo`, `br`, `cl`, `co`, `ec`, `gf`, `gy`, `pe`, `py`, `sr`, `uy` and `ve`.
- The South America collection is identified by the name `south_america`, and the CI collection process must produce a separate South America extract so it can be downloaded without the `global` option.
