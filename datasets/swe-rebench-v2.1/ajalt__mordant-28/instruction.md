Markdown table parsing fails on empty cells
Trying to print a markdown file that contains empty cells fails currently (mordant version 2.0.0-beta2).

```kotlin
fun main() {
    val t = Terminal()
    t.println(Markdown("""
        | Test |
        |------|
        |      |
    """.trimIndent()))
}
```
The parser does not expect to only encounter whitespace.

```Java
Exception in thread "main" java.lang.IllegalArgumentException: fromIndex(1) > toIndex(0)
	at java.util.ArrayList.subListRangeCheck(ArrayList.java:1014)
	at java.util.ArrayList.subList(ArrayList.java:1004)
	at com.github.ajalt.mordant.markdown.MarkdownRenderer.innerInlines(MarkdownRenderer.kt:279)
	at com.github.ajalt.mordant.markdown.MarkdownRenderer.access$innerInlines(MarkdownRenderer.kt:59)
	at com.github.ajalt.mordant.markdown.MarkdownRenderer$parseTableRow$1.invoke(MarkdownRenderer.kt:316)
	at com.github.ajalt.mordant.markdown.MarkdownRenderer$parseTableRow$1.invoke(MarkdownRenderer.kt:312)
	at com.github.ajalt.mordant.table.SectionBuilderInstance.row(TableDslInstances.kt:96)
	at com.github.ajalt.mordant.markdown.MarkdownRenderer.parseTableRow(MarkdownRenderer.kt:312)
	at com.github.ajalt.mordant.markdown.MarkdownRenderer.access$parseTableRow(MarkdownRenderer.kt:59)
	at com.github.ajalt.mordant.markdown.MarkdownRenderer$parseStructure$7$3.invoke(MarkdownRenderer.kt:174)
	at com.github.ajalt.mordant.markdown.MarkdownRenderer$parseStructure$7$3.invoke(MarkdownRenderer.kt:171)
	at com.github.ajalt.mordant.table.TableBuilderInstance.body(TableDslInstances.kt:64)
	at com.github.ajalt.mordant.markdown.MarkdownRenderer$parseStructure$7.invoke(MarkdownRenderer.kt:171)
	at com.github.ajalt.mordant.markdown.MarkdownRenderer$parseStructure$7.invoke(MarkdownRenderer.kt:159)
	at com.github.ajalt.mordant.table.TableDslKt.table(TableDsl.kt:202)
	at com.github.ajalt.mordant.markdown.MarkdownRenderer.parseStructure(MarkdownRenderer.kt:159)
	at com.github.ajalt.mordant.markdown.MarkdownRenderer.parseFile(MarkdownRenderer.kt:87)
	at com.github.ajalt.mordant.markdown.MarkdownRenderer.render(MarkdownRenderer.kt:81)
	at com.github.ajalt.mordant.markdown.Markdown.document(Markdown.kt:25)
	at com.github.ajalt.mordant.markdown.Markdown.render(Markdown.kt:31)
	at com.github.ajalt.mordant.rendering.Widget$DefaultImpls.render$default(Widget.kt:8)
	at com.github.ajalt.mordant.terminal.Terminal.render(Terminal.kt:242)
	at com.github.ajalt.mordant.terminal.Terminal.println(Terminal.kt:201)
	at main(Main.kt:10)
```
I currently have to work around this issue, by putting an invisible character into empty cells.
