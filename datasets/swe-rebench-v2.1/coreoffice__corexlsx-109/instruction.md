API for matching sheet names to sheet paths
> Hi @duodo2412, the value of the cell B14 in this case is not `""`, it's essentially `nil`, because the cell itself is absent in the `.xlsx` file in this case. If you'd like to verify that, you can specify the exact cell:
>
> ```swift
> let cell = worksheet.cells(atColumns: [ColumnReference("B")!], rows: [4])
> ```
>
> My undertstanding is that this will return an empty array `[]` in your case. Does that resolve your issue?

Tks for the your answer .
Can i ask you another question.
![Screen Shot 2020-04-11 at 14 32 09](https://user-images.githubusercontent.com/44747351/79038150-443ecf80-7c01-11ea-8e92-86deb3706354.png)
I have a lot of sheets in xlsx file.
My code:
let sheets: [String] = try file.parseWorksheetPaths() and print result
- After that i change the order of sheet in file and execute my code again. Result is the same before i change the order of sheet .
How can i know exactly the sheet i want to get ( may be i can query with name of sheet ) . Can you help me?
Tks

_Originally posted by @duodo2412 in https://github.com/MaxDesiatov/CoreXLSX/issues/21#issuecomment-612357393_

### Additional contract requirements

Provide this public API on `XLSXFile` for associating worksheet part paths with names from a supplied workbook:

```swift
public func parseWorksheetPathsAndNames(workbook: Workbook) throws -> [(name: String?, path: String)]
```

The returned entries identify worksheet paths and their corresponding sheet names from the supplied workbook, so callers can select a worksheet by name.
