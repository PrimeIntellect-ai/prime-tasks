[ENH] Allow the DepletionReader to capture materials with underscores
Currently, the `DepletionReader` doesn't capture materials with underscores. This is due to the regular expressions used to match the material name and variable name. With variables like `ING_TOX`, the underscores throw off the engine.

### Additional contract requirements

A material name containing underscores must still be parsed correctly when the depletion variable name also contains underscores, including `ING_TOX`. The reader must associate that variable's data with the intended material and make it available as depletion data.
