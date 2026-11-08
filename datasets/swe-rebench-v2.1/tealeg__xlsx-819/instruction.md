Not Able to Write Last Cell in Pivot Table
I have the following code:
```go
package main

import "github.com/tealeg/xlsx/v3"

func main() {
	f := xlsx.NewFile()
	sh, _ := f.AddSheet("Sheet1")

	// Write Colors (y-axis).
	colors := []string{"Red", "Green", "Blue"}
	for i, clr := range colors {
		cell, _ := sh.Cell(i+1, 0)
		cell.SetString(clr)
	}

	// Write Numbers (x-axis).
	numbers := []string{"1", "2", "3"}
	for i, num := range numbers {
		cell, _ := sh.Cell(0, i+1)
		cell.SetString(num)
	}

	f.Save("Bug.xlsx")
}
```
As you can see I'm trying to write three colors ("Red", "Green" and "Blue") as the Y axis.

However the resulting file looks like this, with the last color is missing.
![Screenshot 2024-07-02 014138](https://github.com/tealeg/xlsx/assets/6254874/79c739ca-f76f-4b19-b0fb-a066db217dab)

Interestingly, I'm able to write the last color if I either write the X axis first, or don't write the X axis at all.

Go version: v1.18
Xlsx version: v3.3.7

Is this expected behaviour? Am I missing some sort of row allocating step?
