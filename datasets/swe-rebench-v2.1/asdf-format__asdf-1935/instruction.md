Remove `refresh_extension_manager`
# Description of the problem

`AsdfFile.schema_info` and `AsdfFile.info` have an argument `refresh_extension_manager`. This ultimately triggers:
https://github.com/asdf-format/asdf/blob/dd84c660feb25b46726e48086d34503733d08915/asdf/_node_info.py#L108-L117
Which loads a fresh default "extension_manager" using default extensions.

This option is entirely unused by downstream and could be deprecated (or perhaps just removed). I am also not sure it needs to be used internally (a quick test at removing it resulted in no test failures).
