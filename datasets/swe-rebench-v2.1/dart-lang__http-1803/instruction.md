`MediaType` is not exported to parent project
When I use `MultipartFile` constructors I could not specify the `contentType` property because `MediaType` from `http_parser` package is used internally in `multipart_file.dart` file and not exported into the target project.
