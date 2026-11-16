1.7.0-rc bug: Private types can be used by other modules
```
src
├── bug.gleam
└── wibble
    └── wobble.gleam
```
Inside wobble.gleam:
```gleam
type Wobble
```
Inside bug.gleam:
```gleam
import wibble/wobble

type Wibble {
  Wibble(wobble.Wobble)
}
```
