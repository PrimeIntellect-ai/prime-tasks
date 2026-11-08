Should be able to cast null type into array
the array should be nil

### Additional contract requirements

- Scanning a document field whose value is null into a Go slice variable with `document.Scan` succeeds and leaves the slice nil.
