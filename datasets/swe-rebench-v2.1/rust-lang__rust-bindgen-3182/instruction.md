version 'sim' in target triple 'aarch64-apple-ios-sim' is invalid
Apple's clang 17 doesn't seem to accept `arm64-apple-ios-sim` anymore, it requires [`arm64-apple-ios-simulator`](https://github.com/search?q=repo%3Allvm%2Fllvm-project+arm64-apple-ios-simulator&type=code), causing errors such as:

    unable to generate bindings: ClangDiagnostic("error: version 'sim' in target triple 'aarch64-apple-ios-sim' is invalid\n")
