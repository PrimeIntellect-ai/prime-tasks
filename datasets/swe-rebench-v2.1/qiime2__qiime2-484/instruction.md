`_FileFormat` Should Have A `.view` Method
**Improvement Description**
`_FileFormat` should have a `.view` method

**Current Behavior**
`BoundFile` objects have a `.view` method allowing for easy transformation between classes, but `_FileFormat` objects do not. This means the easiest way to transform `_FileFormat` objects is to create a directory format with them as a bound file and then use their `.view`.

**Proposed Behavior**
Add a `.view` method to `_FileFormat`

### Additional contract requirements

Calling `.view(target_type)` on a file format applies an available registered transformation and returns the converted value as an instance of the requested type.
