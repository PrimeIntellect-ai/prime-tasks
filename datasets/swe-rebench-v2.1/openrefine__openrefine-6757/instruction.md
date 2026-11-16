Exception error raised when opening a CSV with large number of columns
I have some CSVs and TSVs which have hundreds of columns and which don't open in OpenRefine. I don't really mind that there is a limit on columns, but when it attempts to open such files (into the parsing page after selecting the file) a popup window is shown with a java exception. Here is the message in the popup I got when opening a TSV with 1176 columns:

java.lang.ArrayIndexOutOfBoundsException - Index 512 out of bounds for length 512
Parser Configuration: TsvParserSettings:
	Auto configuration enabled=true
	Auto-closing enabled=true
	Column reordering enabled=true
	Header extraction enabled=null
	Headers=null
	Ignore leading whitespaces=true
	Ignore trailing whitespaces=true
	Input buffer size=1048576
	Input reading on separate thread=true
	Length of content displayed on error=-1
	Line separator detection enabled=false
	Maximum number of characters per column=262144
	Maximum number of columns=512
	Null value=null
	Number of records to read=all
	Processor=none
	Restricting data in exceptions=false
	RowProcessor error handler=null
	Selected fields=none
	Skip bits as whitespace=true
	Skip empty lines=trueFormat configuration:
	TsvFormat:
		Comment character=#
		Escape character=\
		Line separator (normalized)=\n
		Line separator sequence=\n
Internal state when error was thrown: line=0, column=513, record=0, charIndex=18558

I think OR should, instead, throw up a short message stating the column limit (I'm guessing it's 512 based on the above error). It would be even better if OR could handle more columns.

I'm using OpenRefine 3.8.2 on Safari 17.5 on MacOS 14.5

### Additional contract requirements

- CSV and TSV imports must successfully import files with 16,384 columns, including all column headers and values.
