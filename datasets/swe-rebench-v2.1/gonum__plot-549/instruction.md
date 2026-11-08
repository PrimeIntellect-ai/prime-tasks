plot/plotter: HeatMap panics for single-row/single-column grids
### What are you trying to do?
Create and plot a HeatMap with a grid containing a single column. (I observe the same problem with a grid with a single row.)

### What did you do?
The below is an almost-minimal example, based on heat_test.go. The only relevant change is the change of the input data matrix.
```
package main

import (
	"fmt"
	"log"
	"math"
	"os"

	"gonum.org/v1/gonum/mat"
	"gonum.org/v1/plot"
	"gonum.org/v1/plot/palette"
	"gonum.org/v1/plot/plotter"
	"gonum.org/v1/plot/vg/draw"
	"gonum.org/v1/plot/vg/vgimg"
)

type offsetUnitGrid struct {
	XOffset, YOffset float64

	Data mat.Matrix
}

func (g offsetUnitGrid) Dims() (c, r int)   { r, c = g.Data.Dims(); return c, r }
func (g offsetUnitGrid) Z(c, r int) float64 { return g.Data.At(r, c) }
func (g offsetUnitGrid) X(c int) float64 {
	_, n := g.Data.Dims()
	if c < 0 || c >= n {
		panic("column index out of range")
	}
	return float64(c) + g.XOffset
}
func (g offsetUnitGrid) Y(r int) float64 {
	m, _ := g.Data.Dims()
	if r < 0 || r >= m {
		panic("row index out of range")
	}
	return float64(r) + g.YOffset
}

type integerTicks struct{}

func (integerTicks) Ticks(min, max float64) []plot.Tick {
	var t []plot.Tick
	for i := math.Trunc(min); i <= max; i++ {
		t = append(t, plot.Tick{Value: i, Label: fmt.Sprint(i)})
	}
	return t
}

func ExampleHeatMap() {
	m := offsetUnitGrid{
		XOffset: 0,
		YOffset: 0,
		Data: mat.NewDense(1, 2, []float64{
			1, 2,
		})}
	pal := palette.Heat(12, 1)
	h := plotter.NewHeatMap(m, pal)

	p, err := plot.New()
	if err != nil {
		log.Panic(err)
	}
	p.Title.Text = "Heat map"

	p.X.Tick.Marker = integerTicks{}
	p.Y.Tick.Marker = integerTicks{}

	p.Add(h)

	img := vgimg.New(250, 175)
	dc := draw.New(img)

	p.Draw(dc)
	w, err := os.Create("heatMap.png")
	if err != nil {
		log.Panic(err)
	}
	png := vgimg.PngCanvas{Canvas: img}
	if _, err = png.WriteTo(w); err != nil {
		log.Panic(err)
	}
}

func main() {
	ExampleHeatMap()
}
```

### What did you expect to happen?
I expected a HeatMap with a single column to be produced.

### What actually happened?
Instead, the code panics, telling me:
```
$ go run test_heatmap.go
panic: row index out of range

goroutine 1 [running]:
main.offsetUnitGrid.Y(0x0, 0x0, 0x15259e0, 0xc0000bf640, 0x1, 0x0)
	/tmp/src/test_heatmap.go:35 +0x83
gonum.org/v1/plot/plotter.(*HeatMap).Plot(0xc000082180, 0x152a200, 0xc0000a95f0, 0x4038948000000000, 0x4037108000000000, 0x406f400000000000, 0x4063f2b000000000, 0xc000228400)
	/tmp/src/gonum.org/v1/plot/plotter/heat.go:133 +0xeeb
gonum.org/v1/plot.(*Plot).Draw(0xc000228400, 0x152a080, 0xc0000821e0, 0x0, 0x0, 0x406f400000000000, 0x4063f2b000000000)
	/tmp/src/gonum.org/v1/plot/plot.go:165 +0x92e
main.ExampleHeatMap()
	/tmp/src/test_heatmap.go:74 +0x32a
main.main()
	/tmp/src/test_heatmap.go:86 +0x20
exit status 2
```

[HIDDEN] The problem I encountered when I tried this, though, is that the GridXYZ interface does not expose the required information about the grid cell sizes.
NOTE: Without claiming to actually understand the code quite yet, this makes me believe that the current implementation is only correct for grids with constant cell sizes(?).

### What version of Go and Gonum/plot are you using?
Go: go version go1.12.2 darwin/amd64
Gonum/plot: 06eadbae218595eae650257c1d591e64364c76d7

### Does this issue reproduce with the current master?
Yes, it does.
