nyc instrument should resolve source filenames.
Create ./somefile.js then run `nyc instrument somefile.js`.  The instrumented code produces coverage data for the filename `'somefile.js'` when it really should be producing coverage for `path.resolve('somefile.js')`.  This causes oddness in reporting when combining pre-instrumented code with code that nyc instruments on the fly (during execution).

CC @AndrewFinlay
