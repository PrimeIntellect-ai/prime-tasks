Recent bug with nil TEXT and BLOB columns
I made a quick reproduction of the bug. tl;dr: A null value in a text or blob column returns a []byte{0} presumably something wants to return an empty string in such cases now.


```go
package repro

import (
        "database/sql"
        "fmt"

        _ "github.com/mattn/go-sqlite3"
)

func Example() {
        db, _ := sql.Open("sqlite3", "main.db")
        db.Exec("create table tbl (txt text)")
        var b []byte
        db.Exec("insert into tbl (txt) values (?)", &b)
        rows, _ := db.Query("select txt from tbl ")
        rows.Next()
        rows.Scan(&b)
        fmt.Printf("%#v\n", b)

        // Output:
        // []byte(nil)
}

// Actual:
// --- FAIL: Example (0.01s)
// got:
// []byte{0x0}
// want:
// []byte(nil)
// FAIL
// exit status 1
// FAIL repro   0.011s
```
