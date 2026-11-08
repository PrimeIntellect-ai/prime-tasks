Backticks appearing in tags are not properly handled
## Problem statement

If schema data containing backticks end up in struct (etc.) tags of generated Go code, the tag generation is not handling quotation of tags properly. ( Outer quotes would need to be " instead of backtick with inner double quotes being escaped. One solution is to do this with _all_ tags, but that would make the generated code ugly,  and `go fmt` doesn't clean it up.)

## Swagger specification

Backticks are legal, e.g. in `XMLObject`, the [name](https://swagger.io/specification/v2/#xmlObject) parameter is a `string` with no further restrictions ...

## Steps to reproduce

I've attached a minimal extract from a real-world public schema (https://api.mouser.com/api/docs/ui/index) which ends up generating broken code.  Executed as (`swagger generate client -f test.json.txt`), here are the relevant bits:

```
// schema
"xml" : {
    "name" : "KeyValuePair`2",
    "wrapped" : true
}
// go IS
(...) `json:"ScheduledReleases" xml:"KeyValuePair`2"`

// go SHOULD
(...) "json:\"ScheduledReleases\" xml:\"KeyValuePair`2\""
```

[test.json.txt](https://github.com/go-swagger/go-swagger/files/5538040/test.json.txt)

Unfortunately, you can't escape backticks within backticks, so Tags need to revert to double quotes containing escaped quotation marks ...

(Also, I'm well aware that this is _terribly awfully unaesthetic_ style and it leaves me scratching my head asking myself what sort of a _deranged monster_ would do such a thing, but as far as I can tell it's perfectly legal.)

## Environment
swagger version: current (2020-11-13) master (  8831a62b )
go version: ```
go version go1.14.3 linux/amd64```
OS:
```
$ lsb_release  -a
No LSB modules are available.
Distributor ID:	Ubuntu
Description:	Ubuntu 20.04.1 LTS
Release:	20.04
Codename:	focal
```

### Additional contract requirements

Struct field tags for model properties are rendered by the public method
`PrintTags` on `GenSchema` (in `generator/structs.go`), which returns the complete
Go struct field tag literal as a string.

The rendered tag combines a JSON tag, carrying the `omitempty` modifier when
the field is not required and empty values are omitted, and the `string` modifier
when applicable; an XML tag when an XML name is present, carrying the
`omitempty` modifier when applicable; and the tags requested through
`StructTags`. When the `example` tag is requested, it carries the schema
example value.
Any additional custom tag is included as well.

When any tag value contains a backtick, the whole tag is rendered as a double-quoted
Go string literal with escaped inner quotes instead of a raw backtick literal.
