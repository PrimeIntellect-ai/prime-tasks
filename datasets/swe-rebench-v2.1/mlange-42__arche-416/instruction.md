panic on `filter.compile` with more than 16 components
Hi, I was playing with the lib and Ebitengine to create a simple word game.
Everything was working as expected with no issues until I tried to add the 17th component. I was not able to have a minimal reproducible example, but I'll try to make one next week.
I am opening the issue to start talking about the problem.

If I have 16 components everything is working great, no issues there.
As soon as I add a new component (I created a simple boolean component in case the error was related to the pointer to the sprite):

Component:

```go
package component

type BgSprite struct {
	Active bool
}
```

Entity:

```go
package entity

import (
	"github.com/hanchon/wordgame/pkg/games/cruzadas/component"
	"github.com/mlange-42/arche/ecs"
	"github.com/mlange-42/arche/generic"
)

func NewBackground(w *ecs.World) {
	mapper := generic.NewMap1[component.BgSprite](w)
	entity := mapper.New()
	a := mapper.Get(entity)
	a.Active = false
}
```

Scene loader:

```go
func LoadScene(world *ecs.World) *types.SceneFunctions {
	sf := types.NewSceneFunctions()
	// Entities
	currentUserInput := controller.Mouse{}
	entity.NewController(world, &currentUserInput)
	entity.NewCircle(world)
	entity.NewBackground(world)

	letters := []rune{'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'}
	entity.NewLettersInCircle(world, letters)
	entity.NewWordsToGuest(world, letters)

	// Systems
	sf.AddSystems(
		[]types.System{
			system.NewDrawCircleSystem(world),
			system.NewDrawActiveLineSystem(world),
			system.NewDrawLettersInCircleSystem(world),
			system.NewDrawActiveWordSystem(world),
			system.NewUserInputSystem(world),
			system.NewCollideWithLettersSystem(world),
			system.NewCheckInputedWordSystem(world),
			system.NewDrawGridSystem(world),
			system.NewDrawDiscoveredLettersSystem(world),
		},
	)

	return sf
}
```

After adding the line `entity.NewBackground(world)`, my draw function started to panic. Without that line, everything works as expected.

Panic error:

```sh
2024-04-28 13:53:24.581 main[12782:10271293] [CAMetalLayer nextDrawable] returning nil because allocation failed.
panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x2 addr=0x0 pc=0x101143af4]

goroutine 67 [running]:
github.com/mlange-42/arche/ecs.(*archetype).ExtendLayouts(...)
        /Users/hanchon/go/pkg/mod/github.com/mlange-42/arche@v0.11.1-0.20240422140523-1f3a73586dbf/ecs/archetype.go:270
github.com/mlange-42/arche/ecs.(*archNode).ExtendArchetypeLayouts(0x14000228c08?, 0x0?)
        /Users/hanchon/go/pkg/mod/github.com/mlange-42/arche@v0.11.1-0.20240422140523-1f3a73586dbf/ecs/archetype_node.go:140 +0x44
github.com/mlange-42/arche/ecs.(*World).extendArchetypeLayouts(0x140003ce488, 0x20)
        /Users/hanchon/go/pkg/mod/github.com/mlange-42/arche@v0.11.1-0.20240422140523-1f3a73586dbf/ecs/world_internal.go:1081 +0x44
github.com/mlange-42/arche/ecs.(*World).componentID(0x140003ce488, {0x1013e6420, 0x101379500})
        /Users/hanchon/go/pkg/mod/github.com/mlange-42/arche@v0.11.1-0.20240422140523-1f3a73586dbf/ecs/world_internal.go:1094 +0xc8
github.com/mlange-42/arche/ecs.TypeID(...)
        /Users/hanchon/go/pkg/mod/github.com/mlange-42/arche@v0.11.1-0.20240422140523-1f3a73586dbf/ecs/functions.go:37
github.com/mlange-42/arche/generic.toIds(0x140003ce488, {0x14000219a40, 0x3, 0x0?})
        /Users/hanchon/go/pkg/mod/github.com/mlange-42/arche@v0.11.1-0.20240422140523-1f3a73586dbf/generic/util.go:37 +0x5c
github.com/mlange-42/arche/generic.(*compiledQuery).Compile(0x14000001930, 0x140003ce488, {0x14000219a40?, 0x14000035828?, 0x10117ce80?}, {0x0, 0x0, 0x0}, {0x0, 0x0, ...}, ...)
        /Users/hanchon/go/pkg/mod/github.com/mlange-42/arche@v0.11.1-0.20240422140523-1f3a73586dbf/generic/compiled.go:37 +0x84
github.com/mlange-42/arche/generic.(*Filter3[...]).Filter(0x101147e7c, 0x140000358b8?, {0x0?, 0x0, 0x0})
        /Users/hanchon/go/pkg/mod/github.com/mlange-42/arche@v0.11.1-0.20240422140523-1f3a73586dbf/generic/query_generated.go:712 +0x84
github.com/mlange-42/arche/generic.(*Filter3[...]).Query(0x3fd0000000000000, 0x140003ce488?, {0x0, 0x1013dd5c0?, 0x1400048e140?})
        /Users/hanchon/go/pkg/mod/github.com/mlange-42/arche@v0.11.1-0.20240422140523-1f3a73586dbf/generic/query_generated.go:739 +0x50
github.com/hanchon/wordgame/pkg/games/cruzadas/system.(*DrawActiveWord).Draw(0x14000538698?, 0x14000148cb0)
        /Users/hanchon/devel/hanchon/wordgame/pkg/games/cruzadas/system/draw_active_word.go:28 +0x48
github.com/hanchon/wordgame/pkg/scenes/types.(*SceneFunctions).Draw(...)
        /Users/hanchon/devel/hanchon/wordgame/pkg/scenes/types/functions.go:20
github.com/hanchon/wordgame/pkg/games/cruzadas.(*CruzadasScene).Draw(0x140000da180?, 0x14000148cb0)
        /Users/hanchon/devel/hanchon/wordgame/pkg/games/cruzadas/scene.go:26 +0x4c
github.com/joelschutz/stagehand.(*SceneManager[...]).Draw(...)
```

Draw function:

```go
type DrawActiveWord struct {
	world  *ecs.World
	filter *generic.Filter3[component.ActiveWord, component.Position, component.Color]
}

func NewDrawActiveWordSystem(world *ecs.World) *DrawActiveWord {
	return &DrawActiveWord{
		world:  world,
		filter: generic.NewFilter3[component.ActiveWord, component.Position, component.Color](),
	}
}

func (c *DrawActiveWord) Draw(screen *ebiten.Image) {
	res := c.filter.Query(c.world)
	if !res.Next() {
		return
	}

	word, pos, color := res.Get()
	res.Close()

	scale := 0.20
	spriteSize := constants.SpriteSize * scale

	rectLenght := float32(len(word.Word) * int(spriteSize))

	radius := spriteSize / 2

	startX := pos.X - rectLenght/2
	startY := pos.Y - 10

	rectStartX := startX
	rectStartY := startY - float32(radius)

	vector.DrawFilledCircle(screen, startX, startY, float32(radius), color.Color, true)
	vector.DrawFilledRect(screen, rectStartX, rectStartY, rectLenght, float32(spriteSize), color.Color, true)
	vector.DrawFilledCircle(screen, rectStartX+rectLenght, startY, float32(radius), color.Color, true)

	for i, v := range word.Word {
		letters.WhiteLetters[v].Draw(
			screen,
			ganim8.DrawOpts(float64(rectStartX)+spriteSize*float64(i), float64(rectStartY), 0, scale, scale),
		)
	}

}
```

I went deep into the panic error and I found that the issue in related to the `compile` function for the filter. Used in the line `res := c.filter.Query(c.world)`.
The problem is that the `*ecs.archetype` is `nil` but I can not figure it out why. The file is `arche/ecs/archetype.go` and here `a` is `nil`, so `a.layouts` is the reason of the panic.
```go
func (a *archetype) ExtendLayouts(count uint8) {
	if len(a.layouts) >= int(count) {
		return
	}
	temp := a.layouts
	a.layouts = make([]layout, count)
	copy(a.layouts, temp)
	a.archetypeAccess.basePointer = unsafe.Pointer(&a.layouts[0])
}
```

If I create new entities using any other component the program works without any issue, but as soon as I try to use the `BgSprite` component I get the panic.

Sorry for the wall of text, maybe you can find my issue with this information, but I'll try to make a smaller example to replicate my issue so it's easier to debug.

Thanks

PD: I am using the current `main` (`1f3a73586dbf70c153a535bac5666fa72f1b02f1`) but I also tried the `v0.11.0` tag and I found the same issue.
PD2: I tried also to recreate the filter each time inside the draw function, but I got the same panic.
PD3: If i keep adding more components different filters calls start to panic, I think that is related to the pages that are changing in the file `arche/ecs/utils.go`
```go
// Get returns the value at the given index.
func (p *pagedSlice[T]) Get(index int32) *T {
	return &p.pages[index/pageSize][index%pageSize]
}
```

Debugger screenshots included:
![Screenshot 2024-04-28 at 14 07 19](https://github.com/mlange-42/arche/assets/5675227/c9b563bd-fa10-448d-9506-a7df5ae9e344)
![Screenshot 2024-04-28 at 14 07 07](https://github.com/mlange-42/arche/assets/5675227/9729c1ca-1304-43ef-b30b-747b5475bcec)
