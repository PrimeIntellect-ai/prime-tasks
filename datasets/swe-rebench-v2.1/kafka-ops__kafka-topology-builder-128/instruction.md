Schemas for values without corresponding schema for key should be supported
Currently KTB throws a null-pointer exception when a schema-file for values is specified without providing a schema file for the corresponding key.

It should be possible to just specify a value schema.
