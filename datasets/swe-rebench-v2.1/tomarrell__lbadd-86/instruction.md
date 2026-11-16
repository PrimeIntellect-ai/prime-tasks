parser: literal must be allowed to be a single question mark
Prepared statements require placeholders, which shall be literals with the content `?`.
They must be emitted as common literals. The executor can then expect the arguments, one for every placeholder.
