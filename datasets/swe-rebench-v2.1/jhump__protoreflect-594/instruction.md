Regression upgrading from v1.14.1 to v1.15.4: absolute paths no longer accepted by parser.ParseFilesButDoNotLink
Here’s a small test program that breaks when upgrading:

```
% cat repro.go
package main

import (
	"log"
	"os"
	"path/filepath"

	"github.com/jhump/protoreflect/desc/protoparse"
)

func main() {
	tempdir, err := os.MkdirTemp("", "protoparse")
	if err != nil {
		log.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(tempdir, "extra.proto"), []byte("package extra;"), 0644); err != nil {
		log.Fatal(err)
	}
	mainPath := filepath.Join(tempdir, "main.proto")
	if err := os.WriteFile(mainPath, []byte("package main; import \"extra.proto\";"), 0644); err != nil {
		log.Fatal(err)
	}
	parser := protoparse.Parser{
		ImportPaths: []string{tempdir},
	}

	fds, err := parser.ParseFilesButDoNotLink(mainPath)
	if err != nil {
		log.Fatal(err)
	}
	log.Printf("got %d fds", len(fds))
}

% cat go.mod
module protoparse1

go 1.21.5

require github.com/jhump/protoreflect v1.14.1 // indirect

% go run repro.go
2024/01/19 16:31:20 got 1 fds

% go get github.com/jhump/protoreflect@v1.15.4
go: upgraded github.com/jhump/protoreflect v1.14.1 => v1.15.4

% go run repro.go
2024/01/19 16:31:24 open /tmp/protoparse337034822/tmp/protoparse337034822/main.proto: no such file or directory
exit status 1
```

Is this change intentional or should the behavioral change be corrected?
