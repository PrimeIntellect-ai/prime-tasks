Detect and warn about elaboratables added more than once into the hierarchy

### Additional contract requirements

- Add a public exception `DuplicateElaboratable` in module `amaranth.hdl._ir`. When the same elaboratable object is added to the hierarchy more than once, elaboration raises `DuplicateElaboratable` with a message describing the duplication.
