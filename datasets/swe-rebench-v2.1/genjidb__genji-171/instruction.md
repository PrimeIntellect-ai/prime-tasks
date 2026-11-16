query on indexed field only returns 29 records
If I run a query on an indexed field where there are 100 duplicate records in the database, I only get 29 results. For a similar field that is not indexed, a query returns the full 100 documents. Is this expected?

Source for test: https://github.com/simpleiot/simpleiot/tree/feature-genji/cmd/genji-test2

output of test:

```
2020/08/27 10:54:50 SELECT * FROM tests WHERE field1 = "test1": documents found: 29, time: 306.057µs
2020/08/27 10:54:50 SELECT * FROM tests WHERE field2 = "test1": documents found: 100, time: 618.836µs
2020/08/27 10:54:50 indexed field returned 29 records, non indexed filed returned 100 records, expected 100 records for both
2020/08/27 10:54:50 All done :-)
```

test source:

```go
package main

import (
	"log"
	"time"

	"github.com/genjidb/genji"
	"github.com/genjidb/genji/database"
	"github.com/genjidb/genji/document"
)

// Test type
type Test struct {
	Field1 string
	Field2 string
}

// returns true if db already exists
func setup(db *genji.DB) bool {
	err := db.Exec("CREATE TABLE tests;")
	if err != nil {
		if err != database.ErrTableAlreadyExists {
			log.Fatal("error creating tests: ", err)
		}
	}

	err = db.Exec("CREATE INDEX idx_tests_field1 ON tests(field1)")
	if err != nil {
		if err != database.ErrIndexAlreadyExists {
			log.Fatal("error creating index: ", err)
		}
		return true
	}

	return false
}

func populateData(db *genji.DB) {
	// insert first user, then a lot of another user
	t := Test{
		Field1: "test1",
		Field2: "test1",
	}

	count := 100
	for i := 0; i < count; i++ {
		err := db.Exec("INSERT INTO tests VALUES ?", &t)
		if err != nil {
			log.Fatal("Error inserting test: ", err)
		}
	}
}

// returns # of docs found
func query(db *genji.DB, q string) int {
	start := time.Now()

	res, err := db.Query(q)

	if err != nil {
		log.Fatal("query error: ", err)
	}

	defer res.Close()

	count := 0

	err = res.Iterate(func(d document.Document) error {
		t := Test{}
		err := document.StructScan(d, &t)
		if err != nil {
			log.Fatal("Error scanning document: ", err)
		}

		count++

		return nil
	})

	log.Printf("%v: documents found: %v, time: %v", q, count, time.Since(start))
	return count
}

func main() {
	db, err := genji.Open(":memory:")

	if err != nil {
		log.Fatal(err)
	}

	defer db.Close()

	dataExists := setup(db)

	if !dataExists {
		populateData(db)
	}

	// look for the record at the beginning of the collection
	count1 := query(db, `SELECT * FROM tests WHERE field1 = "test1"`)
	count2 := query(db, `SELECT * FROM tests WHERE field2 = "test1"`)

	if count1 != count2 {
		log.Printf("indexed field returned %v records, non indexed filed returned %v records, expected 100 records for both", count1, count2)
	}

	log.Println("All done :-)")
}

```

### Additional contract requirements

- Add a method `NextSequence() (uint64, error)` to the `engine.Store` interface, implemented by the Badger, Bolt, and Memory stores.
- The first call to `NextSequence` on a store returns `1`; each subsequent call returns the previous value plus one. The last generated value is persisted across transactions, so a call made in a later transaction continues from the previous value.
- `NextSequence` requires a writable transaction. On a read-only transaction it returns `engine.ErrTransactionReadOnly`.
