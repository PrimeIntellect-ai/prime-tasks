Possible bug with inserting extra space between string literal and dot symbol
### Description

Not sure if this is bug or I'm doing some not allowed operation but please take a look.

let's consider such small macro
```swift
import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

public struct TestMacro: PeerMacro {
    public static func expansion(
        of node: SwiftSyntax.AttributeSyntax,
        providingPeersOf declaration: some SwiftSyntax.DeclSyntaxProtocol,
        in context: some SwiftSyntaxMacros.MacroExpansionContext
    ) throws -> [SwiftSyntax.DeclSyntax] {

        guard let declaration = declaration.as(FunctionDeclSyntax.self) else {
            fatalError()
        }
        let body = declaration.body!.statements
        return ["""
                func test1() {
                    \(raw: body)
                }
                """]
    }
}

@main
struct MyMacro: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        TestMacro.self,
    ]
}
```
and when using in this example
```swift
import MyMacro

struct Struct {
    @TestMacro
    func method() {
        let x = 100
        "Swift Macro".lowercased()
        let y = 123.byteSwapped
    }
}
```
macro is expanded to this code
```swift
func test1() {

        let x = 100
        "Swift Macro" .lowercased()
        let y = 123.byteSwapped
}
```
There is extra space after string literal `Swift Macro` and before `.lowercased()`. As you can notice for int literal in next line  it is working fine.

swift-syntax 509.0.2

Here is link to full macro project.
https://github.com/mkowalski87/swift-macro-issue

### Steps to Reproduce

_No response_
