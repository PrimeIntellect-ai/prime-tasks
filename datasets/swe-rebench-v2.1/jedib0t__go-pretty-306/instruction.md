Table.SortBy can't handle empty cells
**Describe the bug**

The last column of your test table has no values for two rows. Sorting that column fails.

**To Reproduce**

Put this into table_test.go:

```go
func TestTable_MoreSort(t *testing.T) {
	table := Table{}
	table.AppendRows(testRows)
	table.AppendHeader(testHeader)
	table.SetStyle(styleTest)
	expectedOut := `(-----^------------^-----------^--------^-----------------------------)
[<#  >|<FIRST NAME>|<LAST NAME>|<SALARY>|<                           >]
{-----+------------+-----------+--------+-----------------------------}
[<20 >|<Jon       >|<Snow     >|<  2000>|<You know nothing, Jon Snow!>]
[<300>|<Tyrion    >|<Lannister>|<  5000>|<                           >]
[<1  >|<Arya      >|<Stark    >|<  3000>|<                           >]
\-----v------------v-----------v--------v-----------------------------/`
	table.SortBy([]SortBy{{Number: 5, Mode: Dsc}, {Name: "Last Name", Mode: Asc}})
	assert.Equal(t, expectedOut, table.Render())
}
```

**Expected behavior**

Expactation is that empty cells are sorted according to their string, representation.

The expected output is given in the code.

**Screenshots**

Actual output:

```text
(-----^------------^-----------^--------^-----------------------------)
[<  #>|<FIRST NAME>|<LAST NAME>|<SALARY>|<                           >]
{-----+------------+-----------+--------+-----------------------------}
[<300>|<Tyrion    >|<Lannister>|<  5000>|<                           >]
[< 20>|<Jon       >|<Snow     >|<  2000>|<You know nothing, Jon Snow!>]
[<  1>|<Arya      >|<Stark    >|<  3000>|<                           >]
\-----v------------v-----------v--------v-----------------------------/
```

As you see: Column 5 isn't properly sorted.

**Software (please complete the following information):**
 - OS: Mac OS - But I'm using a dockerized go
 - GoLang Version dockerized golang:latest

### Additional contract requirements

- Add the public `SortMode` values `AscAlphaNumeric`, `AscNumericAlpha`, `DscAlphaNumeric` and `DscNumericAlpha` to the `table` package (`github.com/jedib0t/go-pretty/v6/table`), usable in `SortBy.Mode`:
  - `AscAlphaNumeric`: values that are not numbers come before values that are numbers; the non-numeric values are ordered ascending as strings and the numeric values are ordered ascending by value.
  - `AscNumericAlpha`: values that are numbers come before values that are not numbers; the numeric values are ordered ascending by value and the non-numeric values are ordered ascending as strings.
  - `DscAlphaNumeric`: values that are not numbers come before values that are numbers; the non-numeric values are ordered descending as strings and the numeric values are ordered descending by value.
  - `DscNumericAlpha`: values that are numbers come before values that are not numbers; the numeric values are ordered descending by value and the non-numeric values are ordered descending as strings.
