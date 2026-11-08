[Feature Request] - Table full width based on terminal size / Header / Row content auto positioning
**Is your feature request related to a problem? Please describe.**
Tables with and column spacing seem to be dependent on row content

Header / Row content alignment, I found in using the `text.Hyperlink(text, link)` it table formatting

**Describe the solution you'd like**
A  config option allow the table to calculate no only the full table width, but also split the header / column locations based on the terminal size

Header / Row content alignment, I found in using the `text.Hyperlink(text, link)` seems to break the content alignment

**Describe alternatives you've considered**
Tried adjusting the `.SetColumnConfigs( WidthMin, WidthMax)`

**Additional context**

Examples:

#### using regular non hyperlink - works as expected, wish I could force it to be the full size of the terminal with everything aligned perfectly
![image](https://github.com/user-attachments/assets/97882f2f-b3ac-4655-8460-95590e35823e)
![image](https://github.com/user-attachments/assets/9fd2f58a-a052-42cc-8c98-1b567adae19e)

#### using hyperlink - throws alignment off just a bit
![image](https://github.com/user-attachments/assets/c76f161a-06cb-4e3f-b371-5910d6feff79)
![image](https://github.com/user-attachments/assets/bc59f4e4-a9fa-4b5c-8091-75e397d8e498)

####I was able to find fix the alignment issue by doing the following but it's very hacky and I haven't tested it enough, would be better if this was automagically calculated

![image](https://github.com/user-attachments/assets/c2b8d666-85d5-4ae4-9165-fdd00a53f6d5)
![image](https://github.com/user-attachments/assets/047c28e6-ed06-4e30-94c9-b7de614d7c53)

```go
// DirectoryResults struct for the results
type DirectoryResult struct {
	Directory string
	Count     int
}

// EntryResults struct for more in depth entry info
type EntryResults struct {
	Directory string
	FileName  string
	FileSize  string
}

// The `FormatPath` function converts file paths to either Windows or Unix style based on the operating.
// system specified.
func FormatPath(path, goos string) string {
	switch goos {
	case "windows":
		// Convert to Windows style paths (with backslashes)
		return filepath.FromSlash(path)
	case "linux", "darwin":
		// Convert to Unix style paths (with forward slashes)
		return filepath.ToSlash(path)
	default:
		// Default to Unix style paths
		return path
	}
}

// DetailedResults example
detailedResults := []EntryResults {
    {Directory: "S:\\testdata\\zips", FileName: "tamara.zip", FileSize: "32.37 MB"},
    {Directory: "S:\\testdata\\zips", FileName: "pop.7z", FileSize: "121.22 MB"},
    {Directory: "S:\\testdata\\One\\Videos\\One", FileName: "videofile.mkv", FileSize: "0 B"},
}

// Non Detailed example
nonDetailedResuls := []DirectoryResult {
  {Directory: "s:\\testdata\\One\\Videos\\One", Count: 1},
  {Directory: "s:\\testdata\\zips" , Count: 2},
}

// shared vars
totalCount := 3
totalFileSize := 161061273

// renderResults to table takes and interface and renders the table accordingly.
```go
func renderResultsToTable(results interface{}, totalCount int, totalFileSize int64, ff types.FileFinder) {
	t := table.Table{}

	// Determine header and footer based on the type of results
	var header table.Row
	var footer table.Row
	switch results.(type) {
	case []types.DirectoryResult:
		header = table.Row{"Directory", "\t\tCount"}
		footer = table.Row{"Total", pterm.Sprintf("\t\t  %v", totalCount)}
	case []types.EntryResult:
		header = table.Row{"Directory", "\t\tFileName", "\t\tFileSize"}
		footer = table.Row{"Total", pterm.Sprintf("\t\t  %v", totalCount), pterm.Sprintf("\t\t%v", commonFormatters.FormatSize(totalFileSize))}
	default:
		return // Exit if results type is not supported
	}

	t.AppendHeader(header)

	// Append rows based on the display mode
	switch results := results.(type) {
	case []types.DirectoryResult:
		for _, result := range results {
			t.AppendRow(table.Row{
				text.Hyperlink(commonFormatters.FormatPath(result.Directory, runtime.GOOS), result.Directory),
				pterm.Sprintf("\t   %v", result.Count),
			})
		}
	case []types.EntryResult:
		if ff.DisplayDetailedResults {
			for _, result := range results {
				t.AppendRow(table.Row{
					text.Hyperlink(commonFormatters.FormatPath(result.Directory, runtime.GOOS), result.Directory),
					"\t " + result.FileName,
					"\t " + result.FileSize,
				})
			}
		}
	}

	t.AppendFooter(footer)

	t.SetStyle(table.StyleColoredDark)
	t.SetOutputMirror(os.Stdout)
	t.Render()
}
```

#### another example using colors with hyperlink illustration how alignment is broken - illustration how my temp fix is garbage

```go
func formatResultHyperLink(link, txt string) string {
	text.EnableColors()

	link = commonFormatters.FormatPath(link, runtime.GOOS)
	txt = text.FgGreen.Sprint(txt)

	return text.Hyperlink(link, txt)
}


func renderResultsToTable(results interface{}, totalCount int, totalFileSize int64, ff types.FileFinder) {
	t := table.Table{}

	// Determine header and footer based on the type of results
	var header table.Row
	var footer table.Row
	switch results.(type) {
	case []types.DirectoryResult:
		header = table.Row{"Directory", "Count"}
		footer = table.Row{"Total", pterm.Sprintf("%v", totalCount)}
	case []types.EntryResult:
		header = table.Row{"Directory", "FileName", "FileSize"}
		footer = table.Row{"Total", pterm.Sprintf("%v", totalCount), pterm.Sprintf("%v", commonFormatters.FormatSize(totalFileSize))}
	default:
		return // Exit if results type is not supported
	}

	t.AppendHeader(header)

	// Append rows based on the display mode
	switch results := results.(type) {
	case []types.DirectoryResult:
		for _, result := range results {
			t.AppendRow(table.Row{
				formatResultHyperLink(result.Directory, result.Directory),
				pterm.Sprintf("%v", result.Count),
			})
		}
	case []types.EntryResult:
		if ff.DisplayDetailedResults {
			for _, result := range results {
				newLink := pterm.Sprintf("%s/%s", result.Directory, result.FileName)
				t.AppendRow(table.Row{
					formatResultHyperLink(result.Directory, result.Directory),
					formatResultHyperLink(newLink, result.FileName),
					result.FileSize,
				})
			}
		}
	}

	t.AppendFooter(footer)

	t.SetStyle(table.StyleColoredDark)
	t.SetOutputMirror(os.Stdout)
	t.Render()
}
```
![image](https://github.com/user-attachments/assets/db7a7c5e-b02d-42b1-8f5e-b19ae39ab3d2)
![image](https://github.com/user-attachments/assets/be9f8ddd-d686-42a9-9ab5-31c8ba9f0ce5)

### Additional contract requirements

- Add a public struct type `SizeOptions` in package `table` with two exported integer fields: `WidthMax` and `WidthMin`.
- Add an exported field `Size` of type `SizeOptions` to the public `Style` struct, so a table's size constraints can be configured through `Style().Size`.
- `WidthMax` is the maximum allotted width for a full rendered row. When a row's content would exceed this width, the row is truncated and the truncated row ends with the style's `Box.UnfinishedRow` marker. A value of `0` means no maximum is applied.
- `WidthMin` is the minimum allotted width for a full rendered row. When the natural table width is smaller than this value, the columns are auto-expanded until the overall row width reaches this minimum. A value of `0` means no minimum is applied.

- `WidthMin` is a caller-supplied target width. A caller may choose the available terminal width as that target, but rendering does not automatically detect the current terminal dimensions.
- Hyperlink and color annotations on cell content do not affect the alignment of headers and row content.
