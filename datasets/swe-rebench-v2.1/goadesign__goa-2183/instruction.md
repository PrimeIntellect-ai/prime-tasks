cannot use resource method name "Use"
if I use following method name I get an error.

in resources.go:

Method("use", func() {
		Description("sample description")
		..
   ..
..

error when building the go project:

gen/test/endpoints.go:50:6: type Endpoints has both field and method named Use
