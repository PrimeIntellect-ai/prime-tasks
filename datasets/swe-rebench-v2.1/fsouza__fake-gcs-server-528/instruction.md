[Feature Request] add support for startOffset and endOffset
The GCP storage API allows specifying an inclusive startOffset and exclusive endOffset to fetch a range of objects. The fake storage server ignores both parameters, returning all objects instead.

https://cloud.google.com/storage/docs/json_api/v1/objects/list
