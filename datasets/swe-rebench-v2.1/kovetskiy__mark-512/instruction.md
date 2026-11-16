Sigsegv when block quote contains bold text
## What happened?

```
bash-5.2$ ./mark --compile-only -f foo.md
2024-10-01 16:18:48.389 INFO  processing foo.md
panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x2 addr=0x90 pc=0x1055f65e8]

goroutine 1 [running]:
github.com/kovetskiy/mark/renderer.ParseBlockQuoteType.func1({0x105c0f350, 0x140000b8870}, 0x1)
        /Users/patrick/Documents/GitHub/mark/renderer/blockquote.go:121 +0x158
github.com/yuin/goldmark/ast.walkHelper({0x105c0f350, 0x140000b8870}, 0x1400029f1b8)
        /Users/patrick/go/pkg/mod/github.com/yuin/goldmark@v1.7.4/ast/ast.go:492 +0x34
github.com/yuin/goldmark/ast.walkHelper({0x105c113f0, 0x140002b7300}, 0x1400029f1b8)
        /Users/patrick/go/pkg/mod/github.com/yuin/goldmark@v1.7.4/ast/ast.go:498 +0x8c
github.com/yuin/goldmark/ast.walkHelper({0x105c10790, 0x140002b7200}, 0x1400029f1b8)
        /Users/patrick/go/pkg/mod/github.com/yuin/goldmark@v1.7.4/ast/ast.go:498 +0x8c
github.com/yuin/goldmark/ast.walkHelper({0x105c11750, 0x140002b7180}, 0x1400029f1b8)
        /Users/patrick/go/pkg/mod/github.com/yuin/goldmark@v1.7.4/ast/ast.go:498 +0x8c
github.com/yuin/goldmark/ast.Walk(...)
        /Users/patrick/go/pkg/mod/github.com/yuin/goldmark@v1.7.4/ast/ast.go:487
github.com/kovetskiy/mark/renderer.ParseBlockQuoteType({0x105c11750, 0x140002b7180}, {0x1400003b650, 0x2f, 0x30})
        /Users/patrick/Documents/GitHub/mark/renderer/blockquote.go:102 +0xa4
github.com/kovetskiy/mark/renderer.(*ConfluenceBlockQuoteRenderer).renderBlockQuote(0x140003323f0, {0x105c08750, 0x1400032ca40}, {0x1400003b650, 0x2f, 0x30}, {0x105c11750, 0x140002b7180}, 0x1)
        /Users/patrick/Documents/GitHub/mark/renderer/blockquote.go:188 +0xa8
github.com/yuin/goldmark/renderer.(*renderer).Render.func2({0x105c11750, 0x140002b7180}, 0x1)
        /Users/patrick/go/pkg/mod/github.com/yuin/goldmark@v1.7.4/renderer/renderer.go:166 +0xb4
github.com/yuin/goldmark/ast.walkHelper({0x105c11750, 0x140002b7180}, 0x1400029f420)
        /Users/patrick/go/pkg/mod/github.com/yuin/goldmark@v1.7.4/ast/ast.go:492 +0x34
github.com/yuin/goldmark/ast.walkHelper({0x105c10c10, 0x140000b86c0}, 0x1400029f420)
        /Users/patrick/go/pkg/mod/github.com/yuin/goldmark@v1.7.4/ast/ast.go:498 +0x8c
github.com/yuin/goldmark/ast.Walk(...)
        /Users/patrick/go/pkg/mod/github.com/yuin/goldmark@v1.7.4/ast/ast.go:487
github.com/yuin/goldmark/renderer.(*renderer).Render(0x14000065090, {0x105bfd348, 0x14000332510}, {0x1400003b650, 0x2f, 0x30}, {0x105c10c10, 0x140000b86c0})
        /Users/patrick/go/pkg/mod/github.com/yuin/goldmark@v1.7.4/renderer/renderer.go:161 +0x1c4
github.com/yuin/goldmark.(*markdown).Convert(0x1400032c540, {0x1400003b650, 0x2f, 0x30}, {0x105bfd348, 0x14000332510}, {0x0, 0x0, 0x0})
        /Users/patrick/go/pkg/mod/github.com/yuin/goldmark@v1.7.4/markdown.go:118 +0xf4
github.com/kovetskiy/mark/markdown.CompileMarkdown({0x1400003b650, 0x2f, 0x30}, 0x140002f8c20, {0x140002f7310, 0x6}, {0x10567a1df, 0xb}, 0x3ff0000000000000, 0x0, ...)
        /Users/patrick/Documents/GitHub/mark/markdown/markdown.go:95 +0x564
main.processFile({0x140002f7310, 0x6}, 0x140002f8920, 0x140001f5200, {0x0?, 0x0}, {0x0, 0x0})
        /Users/patrick/Documents/GitHub/mark/main.go:412 +0x8d4
main.RunMark(0x140001f5200)
        /Users/patrick/Documents/GitHub/mark/main.go:283 +0x5c0
github.com/urfave/cli/v2.(*Command).Run(0x140002442c0, 0x140001f5200, {0x14000030080, 0x4, 0x4})
        /Users/patrick/go/pkg/mod/github.com/urfave/cli/v2@v2.27.4/command.go:276 +0x600
github.com/urfave/cli/v2.(*App).RunContext(0x1400021e600, {0x105c05de0, 0x106115d80}, {0x14000030080, 0x4, 0x4})
        /Users/patrick/go/pkg/mod/github.com/urfave/cli/v2@v2.27.4/app.go:333 +0x51c
github.com/urfave/cli/v2.(*App).Run(...)
        /Users/patrick/go/pkg/mod/github.com/urfave/cli/v2@v2.27.4/app.go:307
main.main()
        /Users/patrick/Documents/GitHub/mark/main.go:221 +0x184
```

## What did you expect to happen?

Rendered Markdown containing bold text inside a block quote.

## How can we reproduce the behavior you experienced?

Render the following Markdown `foo.md`:

```markdown
<!-- Space: MySpace -->
<!-- Parent: Parent -->
<!-- Title: whatnot -->

## Foo

> **TL;DR:** Thingy!
> More stuff

Foo
```

with `./mark --compile-only -f foo.md` .

## Further Information (please complete the following information)

* Mark Version (`mark --version`): 11.1.0, commit d5c41f6f1fee0dd8fb21f2ad0de1cb78e3162b68
