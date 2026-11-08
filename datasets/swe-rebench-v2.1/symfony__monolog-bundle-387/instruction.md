use_locking argument ignored for rotating_file handler
When the `use_locking` argument was implemented it was only added to the `stream` handler type, but the `rotating_file` extends it and should also have that argument.

See also: https://github.com/symfony/monolog-bundle/commit/00ed2f3c087e74b462f188b228ff1d428c4ed65e
