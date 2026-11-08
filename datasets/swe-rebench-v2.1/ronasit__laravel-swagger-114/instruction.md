Parse deprecated annotation of a request class
According to the doc https://swagger.io/docs/specification/2-0/paths-and-operations we can use the deprecated param in open api spec

What should we do:
1. mark API as deprecated if `@deprecated` annotation was added to the related form request class
2. update readme with this info
