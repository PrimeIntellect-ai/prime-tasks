[Error]Swift/StringCharacterView.swift:158 Fatal error: String index is out of bounds
Hello.
When I ran Muter, the following error occurred. If anyone knows the solution, please let me know.

### Error Message
```
Analyzing source files to find mutants which can be inserted into your project...
Swift/StringCharacterView.swift:158 Fatal error: String index is out of bounds
zsh: trace trap  muter run
```

### Summay
- Successfully tested
- Occurs in some files, not all　(40/1000 files)
- Error in "ChangeLogicalConnector" or "RelationalOperatorReplacement"


### Target
ex.`return activeFlag && !isNew()`

The above code has been confirmed not to produce any errors by commenting it out.

### Environment
- MacOS: Sonoma 14.1.2
- Xcode: 15.0.1
- Muter: 16

**※Using a translation tool to translate Japanese to English.**

### Additional contract requirements

- Add a method `convertToCharOffset(from:)` on `String` in the `muterCore` module that accepts a UTF-8 byte offset (`Int`) and returns the corresponding character offset (`Int?`).
- A UTF-8 byte offset is valid when it is non-negative, strictly less than the string's UTF-8 byte length, and falls on a character boundary. For a valid offset the method returns the matching character offset; in particular offset `0` maps to character offset `0`.
- The method returns `nil` for a negative offset, for an offset greater than or equal to the string's UTF-8 byte length, and for an offset that falls inside a multi-byte character.
- Running Muter on a source file that contains multi-byte (non-ASCII) characters together with a logical connector (`&&` or `||`) must not crash and must produce the correct logical-connector mutation.
- The same no-crash and correct-mutation requirement applies when the affected mutation is a relational-operator replacement.
