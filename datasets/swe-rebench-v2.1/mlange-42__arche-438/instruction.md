Slices in components are GC'ed
When adding components that contain already populated slices, e.g. with `World.Assign`, slices seem to be garbage collected, causing crashes or undefined behaviour. The same seems to be true for pointers.

For the original report, see discussion #436.

A minimal reproducing example:

```go
package main

import (
	"fmt"

	"github.com/mlange-42/arche/ecs"
	"github.com/mlange-42/arche/generic"
)

type CompWithSlice struct {
	Slice []int
}

func main() {
	world := ecs.NewWorld()

	_ = CreateEntity(&world)

	filter := generic.NewFilter1[CompWithSlice]()
	query := filter.Query(&world)
	for query.Next() {
		c := query.Get()
		fmt.Println(c.Slice)
		if c.Slice[0] != 1 || c.Slice[1] != 2 || c.Slice[2] != 3 {
			panic("unexpected values in slice")
		}
	}
}

func CreateEntity(world *ecs.World) ecs.Entity {
	compId := ecs.ComponentID[CompWithSlice](world)

	entity := world.NewEntity()
	world.Assign(
		entity,
		ecs.Component{
			ID: compId,
			Comp: &CompWithSlice{
				Slice: []int{1, 2, 3},
			},
		},
	)

	return entity
}
```

What works:

- adding the component using `generic.MapX.NewWith`

Workaround:

- add the component, and populate slices afterwards.
