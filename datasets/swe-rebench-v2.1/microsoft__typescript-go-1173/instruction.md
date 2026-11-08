Panic in checkGrammarClassLikeDeclaration on vscode
Testing on vscode at `60e1bdd0b6d6085283ac78879c38dc5b09cb5ab2`:

```
 ./built/local/tsgo -p ~/work/vscode/src --diagnostics
```

```
panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x1 addr=0x8 pc=0x8035ca]

goroutine 5113 [running]:
github.com/microsoft/typescript-go/internal/checker.(*Checker).checkGrammarClassDeclarationHeritageClauses(0xc0533ab008, 0xc00d343170, 0xc00e4d0f08)
        /home/jabaile/work/TypeScript-go/internal/checker/grammarchecks.go:934 +0x3ca
github.com/microsoft/typescript-go/internal/checker.(*Checker).checkGrammarClassLikeDeclaration(0xc0533ab008, 0x40abc2?)
        /home/jabaile/work/TypeScript-go/internal/checker/grammarchecks.go:782 +0x5f
github.com/microsoft/typescript-go/internal/checker.(*Checker).checkClassLikeDeclaration(0xc0533ab008, 0xc00d343170)
        /home/jabaile/work/TypeScript-go/internal/checker/checker.go:4069 +0x32
github.com/microsoft/typescript-go/internal/checker.(*Checker).checkClassDeclaration(0xc0533ab008, 0xc00d343170)
        /home/jabaile/work/TypeScript-go/internal/checker/checker.go:4063 +0xfc
github.com/microsoft/typescript-go/internal/checker.(*Checker).checkSourceElementWorker(0xc0533ab008, 0xc00d343170)
        /home/jabaile/work/TypeScript-go/internal/checker/checker.go:2253 +0x347
github.com/microsoft/typescript-go/internal/checker.(*Checker).checkSourceElement(0xc0533ab008, 0xc0539b70b0?)
        /home/jabaile/work/TypeScript-go/internal/checker/checker.go:2147 +0x4a
github.com/microsoft/typescript-go/internal/checker.(*Checker).checkSourceElements(0xc0533ab008, {0xc00eef7b08, 0x34, 0xc0002cfa80?})
        /home/jabaile/work/TypeScript-go/internal/checker/checker.go:2138 +0x2d
github.com/microsoft/typescript-go/internal/checker.(*Checker).checkSourceFile(0xc0533ab008, {0xd04178, 0x12633e0}, 0xc00e4d0f08)
        /home/jabaile/work/TypeScript-go/internal/checker/checker.go:2110 +0x119
github.com/microsoft/typescript-go/internal/checker.(*Checker).CheckSourceFile(0xc0533ab008, {0xd04178, 0x12633e0}, 0xc00e4d0f08)
        /home/jabaile/work/TypeScript-go/internal/checker/checker.go:2099 +0x5c
github.com/microsoft/typescript-go/internal/compiler.(*Program).CheckSourceFiles.func1-range1(0x74203e3d20292801?)
        /home/jabaile/work/TypeScript-go/internal/compiler/program.go:336 +0x3e
github.com/microsoft/typescript-go/internal/compiler.(*checkerPool).Files.func1(0xc0539b7080)
        /home/jabaile/work/TypeScript-go/internal/compiler/checkerpool.go:82 +0x88
github.com/microsoft/typescript-go/internal/compiler.(*Program).CheckSourceFiles.func1()
        /home/jabaile/work/TypeScript-go/internal/compiler/program.go:335 +0xe2
github.com/microsoft/typescript-go/internal/core.(*parallelWorkGroup).Queue.func1()
        /home/jabaile/work/TypeScript-go/internal/core/workgroup.go:39 +0x50
created by github.com/microsoft/typescript-go/internal/core.(*parallelWorkGroup).Queue in goroutine 1
        /home/jabaile/work/TypeScript-go/internal/core/workgroup.go:37 +0x85
```
