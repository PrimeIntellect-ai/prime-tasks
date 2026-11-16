Tables (and therefore almost all layouts) cannot be empty
This complicates items which are rendered by loops.

Consider
```kotlin
fun thing(strings: List<String>) = verticalLayout {
  for (string in strings) {
    cell("Hi $string!")
  }
}
```

This crashes, and so you have to do something like:
```kotlin
fun thing(strings: List<String>) = if (strings.isEmpty()) {
  Text("")
} else {
  verticalLayout {
    for (string in strings) {
      cell("Hi $string!")
    }
  }
}
```

This occurs for `table`, `grid`, and `verticalLayout`. Weirdly, `horizontalLayout` does not exhibit this behavior (presumably because it always adds a single row which is empty?).

Is there a technical reason to prevent empty layouts?

```kotlin
fun main() {
  val t = Terminal()
  println("Vertical")
  runCatching { t.println(verticalLayout { }) }.exceptionOrNull()?.printStackTrace(System.out)
  println("Horizontal")
  runCatching { t.println(horizontalLayout { }) }.exceptionOrNull()?.printStackTrace(System.out)
  println("Grid")
  runCatching { t.println(grid { }) }.exceptionOrNull()?.printStackTrace(System.out)
  println("Table")
  runCatching { t.println(table { }) }.exceptionOrNull()?.printStackTrace(System.out)
}
```
```
Vertical
java.lang.IllegalArgumentException: Table cannot be empty
	at com.github.ajalt.mordant.table.TableImpl.<init>(Table.kt:80)
	at com.github.ajalt.mordant.table.TableLayout.buildTable(TableLayout.kt:24)
	at com.github.ajalt.mordant.table.VerticalLayoutBuilderInstance.build(TableDslInstances.kt:223)
	at com.github.ajalt.mordant.table.TableDslKt.verticalLayout(TableDsl.kt:298)
	at com.jakewharton.mosaic.MordantKt.main(mordant.kt:12)
	at com.jakewharton.mosaic.MordantKt.main(mordant.kt)
Horizontal

Grid
java.lang.IllegalArgumentException: Table cannot be empty
	at com.github.ajalt.mordant.table.TableImpl.<init>(Table.kt:80)
	at com.github.ajalt.mordant.table.TableLayout.buildTable(TableLayout.kt:24)
	at com.github.ajalt.mordant.table.GridBuilderInstance.build(TableDslInstances.kt:149)
	at com.github.ajalt.mordant.table.TableDslKt.grid(TableDsl.kt:277)
	at com.jakewharton.mosaic.MordantKt.main(mordant.kt:16)
	at com.jakewharton.mosaic.MordantKt.main(mordant.kt)
Table
java.lang.IllegalArgumentException: Table cannot be empty
	at com.github.ajalt.mordant.table.TableImpl.<init>(Table.kt:80)
	at com.github.ajalt.mordant.table.TableLayout.buildTable(TableLayout.kt:24)
	at com.github.ajalt.mordant.table.TableDslKt.table(TableDsl.kt:254)
	at com.jakewharton.mosaic.MordantKt.main(mordant.kt:18)
	at com.jakewharton.mosaic.MordantKt.main(mordant.kt)
```

I am using 2.0.0-beta9.

### Additional contract requirements

- When rendered, an empty `table {}` must produce exactly these lines: `░┌┐`, `░││`, and `░└┘`. An empty `verticalLayout {}` must produce exactly one line: `░`.
