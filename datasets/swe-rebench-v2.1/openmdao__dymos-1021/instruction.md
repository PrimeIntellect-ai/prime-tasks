Polynomial controls don't work with Birkhoff transcription
### Description

Attempting to use a polynomial control causes an error during configure. This occurs only in the Birkhoff transcription and only with polynomial controls
`AttributeError: 'Phase' object has no attribute 'ode_all'`

### Example

https://github.com/OpenMDAO/dymos/blob/master/dymos/examples/brachistochrone/test/test_doc_brachistochrone_polynomial_controls.py

### Dymos Version

1.9.2.-dev

### Relevant environment information

_No response_
