Parser crashes on invalid multi-line literal
The following test case crashes the parser:

```swift
"a""" a a"""
```

```
SwiftParser/StringLiterals.swift:181: Fatal error: The lexer should only add trailing trivia to a string segment if the newline is escaped by a backslash
Please submit a bug report (https://swift.org/contributing/#reporting-bugs) and include the crash backtrace.
Stack dump:
0.      Program arguments: /Users/hamish/src/swift-dev/build/Release/swift-macosx-arm64/bin/swift-frontend -typecheck /Users/hamish/src/swift-test-arena/main.swift -sdk /Users/hamish/src/MacOSX.sdk -debug-diagnostic-names -diagnostic-style=swift
1.      Swift version 6.2-dev (LLVM 4197ac1672a278c, Swift 17cbe28e9d85a32)
2.      Compiling with effective version 5.10
3.      While evaluating request ParseTopLevelDeclsRequest(source_file "/Users/hamish/src/swift-test-arena/main.swift")
4.      While evaluating request ParseSourceFileRequest(source_file "/Users/hamish/src/swift-test-arena/main.swift")
5.      With parser at source location: /Users/hamish/src/swift-test-arena/main.swift:1288:4
Stack dump without symbol names (ensure you have llvm-symbolizer in your PATH or set the environment var `LLVM_SYMBOLIZER_PATH` to point to it):
0  swift-frontend                0x0000000109eec46c llvm::sys::PrintStackTrace(llvm::raw_ostream&, int) + 56
1  swift-frontend                0x0000000109eeabbc llvm::sys::RunSignalHandlers() + 112
2  swift-frontend                0x0000000109eecab4 SignalHandler(int, __siginfo*, void*) + 296
3  libsystem_platform.dylib      0x000000019c836704 _sigtramp + 56
4  libswiftCore.dylib            0x00000001afef795c $ss17_assertionFailure__4file4line5flagss5NeverOs12StaticStringV_SSAHSus6UInt32VtF + 176
5  lib_CompilerSwiftParser.dylib 0x0000000116234d88 $s20_CompilerSwiftParser0C0V38reclassifyNewlineOfLastSegmentAsTrivia33_78149DB072C20084E7D780D86E26C3AFLL24rawStringDelimitersToken020openQuoteHasTrailingE014middleSegmentsSb01_aB6Syntax03RawV6SyntaxVSg_SbSayAI03Rawt7LiteralH10ListSyntaxV7ElementOGztF + 220
6  lib_CompilerSwiftParser.dylib 0x0000000116235120 $s20_CompilerSwiftParser0C0V33postProcessMultilineStringLiteral33_78149DB072C20084E7D780D86E26C3AFLL03rawG15DelimitersToken9openQuote8segments05closeU0Say01_aB6Syntax03RawsX0VG023unexpectedBeforeOpeningU0_AL07openingU0SayAJ0ygh11SegmentListX0V7ElementOGAhM0z13BeforeClosingU0AL07closingU0tALSg_AltLtF + 252
7  lib_CompilerSwiftParser.dylib 0x000000011623324c $s20_CompilerSwiftParser0C0V18parseStringLiteral01_aB6Syntax03Rawef4ExprG0VyF + 3548
8  lib_CompilerSwiftParser.dylib 0x00000001161e12b0 $s20_CompilerSwiftParser0C0V20parseUnaryExpression6flavor7pattern01_aB6Syntax07RawExprI0VAC0K6FlavorO_AC14PatternContextOtF + 592
9  lib_CompilerSwiftParser.dylib 0x00000001161de590 $s20_CompilerSwiftParser0C0V30parseSequenceExpressionElement6flavor7pattern01_aB6Syntax07RawExprJ0VAC0L6FlavorO_AC14PatternContextOtF + 1500
10 lib_CompilerSwiftParser.dylib 0x00000001161dd444 $s20_CompilerSwiftParser0C0V23parseSequenceExpression6flavor7pattern01_aB6Syntax07RawExprI0VAC0K6FlavorO_AC14PatternContextOtF + 72
11 lib_CompilerSwiftParser.dylib 0x00000001162397cc $s20_CompilerSwiftParser0C0V9parseItem33_008C1B0E0A90478841CED0DF9A7053A1LL12isAtTopLevel13allowInitDecl01_aB6Syntax012RawCodeBlockeU0V0E0OSb_SbtF + 1240
12 lib_CompilerSwiftParser.dylib 0x0000000116238e58 $s20_CompilerSwiftParser0C0V18parseCodeBlockItem12isAtTopLevel13allowInitDecl01_aB6Syntax03RawefgO0VSgSb_SbtF + 492
13 lib_CompilerSwiftParser.dylib 0x0000000116237314 $s20_CompilerSwiftParser0C0V22parseCodeBlockItemList12isAtTopLevel13allowInitDecl5until01_aB6Syntax03RawefghQ0VSb_S2bACzXEtF05$s20_ab9Syntax017efgh9C0V01_aB6c35E5parse4fromAcD0H0Vz_tFZAA03RawdefgU19VAHzXEfU_SbAHzXEfU_Tf1nncn_nTm + 144
14 lib_CompilerSwiftParser.dylib 0x000000011626d91c $s20_CompilerSwiftSyntax010SourceFileC0V01_aB6ParserE5parse4fromAcD0F0Vz_tFZ + 68
15 swift-frontend                0x0000000105ce7a3c $s11swiftASTGen15parseSourceFile6buffer10moduleName8filename14declContextPtr4kindSVSo16BridgedStringRefV_A2ISvSgSo0n9GenerateddE4KindVtF + 220
```

### Additional contract requirements

- For this input, the parser must also produce the following recovery output. The numbered markers indicate diagnostic locations, and ℹ️ indicates the note location; markers are not part of the source:

```swift
"a"1️⃣""2️⃣ a3️⃣ a4️⃣ℹ️"""5️⃣
```

In order, locations 1–4 must each report `consecutive statements on a line must be separated by newline or ';'`, with fix-its `insert newline` and `insert ';'`, in that order. Location 5 must report `expected '"""' to end string literal`, with the note `to match this opening '"""'` at ℹ️ and the fix-it `insert '"""'`.

The fixed source must be:

```swift
  "a"
  ""
  a
  a
  """
  """
```
