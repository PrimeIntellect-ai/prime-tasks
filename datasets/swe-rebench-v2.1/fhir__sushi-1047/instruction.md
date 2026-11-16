SUSHI should support nested /input/resources folders when added to path-resource config
SUSHI 2.3.0 added support for using the `path-resource` parameter to specify additional paths that can contain resources.  While this works w/ most paths, it does not work for paths that are nested subfolders under existing supported folders (like `input/resources/nested`).  If you try to do that, SUSHI emits a warning saying it will not add the resource to the IG JSON.

If the user has specifically added the folder via the `path-resource` parameter, then SUSHI should not warn on this case.

See: https://chat.fhir.org/#narrow/stream/215610-shorthand/topic/nested.20folders.20in.20.2Finput.2Fresources.2Fabc/near/274334692
