`Terminal.print()` ignores new line feeds at the end of Strings
I'm trying to interface Mordant with an existing logging structure by implementing the `Appendable` interface and forwarding the methods to Mordant using the `Terminal.print()` method, however I'm noticing that new line feeds at the end of `CharSequences/Strings` are getting ignored. Somehow Mordant is stripping them.

**Sample code:**
```
class TerminalAppendable(private val terminal: Terminal): Appendable {

    override fun append(charSequence: CharSequence): Appendable {
        terminal.print(charSequence)
        return this
    }

    override fun append(charSequence: CharSequence, start: Int, end: Int): Appendable {
        terminal.print(charSequence.subSequence(start, end))
        return this
    }

    override fun append(char: Char): Appendable {
        terminal.print(char.toString())
        return this
    }
}
```

```
val appendable = TerminalAppendable(Terminal())
appendable.appendLine("Foo Bar")
appendable.appendLine("Lorem Ipsum")
// Result:   `Foo BarLorem Ipsum`
// Expected: `Foo Bar\nLorem Ipsum\n`

appendable.append("Foo Bar\n")
appendable.append("Lorem Ipsum\n")
// Result:   `Foo BarLorem Ipsum`
// Expected: `Foo Bar\nLorem Ipsum\n`

appendable.append("Foo\nBar\n")
appendable.append("Lorem\nIpsum\n")
// Result:   `Foo\nBarLorem\nIpsum`
// Expected: `Foo\nBar\nLorem\nIpsum\n`
```
