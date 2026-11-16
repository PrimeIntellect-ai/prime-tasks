no-unsafe-references for addInitScript
no-unsafe-references rule now only targets page.evaluate method. How about to target addInitScript too? This is the same kind of method and we ran in  mistakes with using variables from closure sometimes.
