0.6.0 has extra newline bug with multi custom prefix
test 0.4.3 and 0.5.0 is OK.

with 0.6.0, when we have both org level Prefix and project level Prefix, but the imports does not contians any org level Prefix things, it will put extra newline before project level Preifx

with command:

```
gci diff  -s standard -s default -s 'Prefix(code.example.com)' -s 'Prefix(code.example.com/foo/bar/project)' --skip-generated .
```

so I have org level Prefix `code.example.com`

and

 project level Prefix `code.example.com/foo/bar/project`


`a.go` for re-produce:

```
package demo

import (
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo/options"

	"code.example.com/foo/bar/project/constant"
 )
```

test 0.4.3 and 0.5.0 will not change this.

```
go install github.com/daixiang0/gci@v0.5.0

# or

go install github.com/daixiang0/gci@v0.4.3
```


but 0.6.0 will:

```
go install github.com/daixiang0/gci@v0.6.0
```

```diff
--- a.go
+++ a.go
@@ -4,5 +4,6 @@
 	"go.mongodb.org/mongo-driver/bson"
 	"go.mongodb.org/mongo-driver/mongo/options"

+
 	"code.example.com/foo/bar/project/constant"
  )
```
