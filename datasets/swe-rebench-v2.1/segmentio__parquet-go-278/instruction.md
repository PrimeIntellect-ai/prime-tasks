Incorrect definition level in generic Writer
For the structure  below, if 'TB' is null, the definition level should be 1 (because T1 is defined), not zero. The non-generic writer does the right thing.

```go
package main

import (
	"fmt"
	//"github.com/davecgh/go-spew/spew"
	"github.com/vc42/parquet-go"
	"os"
)

type T2 struct {
	X string `parquet:",dict,optional"`
}

type T1 struct {
	TA *T2
	TB *T2
}

type T struct {
	T1 *T1
}

const nRows = 1

func main() {

	t := T{
		T1: &T1{
			TA: &T2{
				X: "abc",
			},
		},
	}

	f, err := os.OpenFile("/tmp/123.parquet", os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0600)
	if err != nil {
		panic(err)
	}

	fmt.Printf("bad:\n")
	rows := make([]T, nRows)
	gw := parquet.NewGenericWriter[T](f)
	for i := 0; i < nRows; i++ {
		rows[i] = t
	}
	_, err = gw.Write(rows)
	if err != nil {
		panic(err)
	}
	gw.Close()

	fmt.Printf("good:\n")
	fw := parquet.NewWriter(f)
	for i := 0; i < nRows; i++ {
		err = fw.Write(&t)
		if err != nil {
			panic(err)
		}
	}
	fw.Close()

	f.Close()

	//rows2, err := parquet.ReadFile[T]("/tmp/123.parquet")
	//spew.Dump(rows2)
}
```

To get the output below, you need to instrument the 'write.go' with a print statement:
```go
func (c *writerColumn) writeBufferedPage(page BufferedPage) (int64, error) {
	fmt.Printf("col: %v max_def %v def %v\n", c.columnPath, c.maxDefinitionLevel, page.DefinitionLevels())
```

bad:
```
col: T1.TA.X max_def 3 def [3]
col: T1.TB.X max_def 3 def [0]
```

good:
```
col: T1.TA.X max_def 3 def [3]
col: T1.TB.X max_def 3 def [1]
```

The bug causes the google big query loader crash.
