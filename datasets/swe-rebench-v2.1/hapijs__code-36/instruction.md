Throw original error when not.exist(err) is asserted
When you do `expect(err).to.not.exist()` you really want the error information, not that some object was expected to be undefined.
