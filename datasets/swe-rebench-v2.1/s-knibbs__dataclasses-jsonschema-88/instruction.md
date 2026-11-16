Improve handling of None in from_object
Currently a `ValueError` is raised in `from_object` if the source object has a `None` value for an enum or nested object field.
