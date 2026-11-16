Calling `ResultSet#getMetaData()` more than once before calling `ResultSet#next()` skips a row
If the client application calls `ResultSet#getMetaData()` more than once **before** calling `ResultSet#next()`, the `ResultSet` will skip the first row of the results when `ResultSet#next()` is called. Calling `ResultSet#getMetaData()` once before calling `ResultSet#next()` will not have this effect.
