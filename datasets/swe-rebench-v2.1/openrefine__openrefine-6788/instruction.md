File type detection fails when multiple files are imported at once
The heuristic to detect file types seems to have a weird behavior when working on multiple files, even though those files have a consistent file type which OpenRefine is able to detect correctly when they are imported individually

### To Reproduce
Steps to reproduce the behavior:

Create two text files `test.md` and `test2.md`, both containing the following content:
```
## Markdown test

This is a [test](https://gnu.org) test
```

2. Import both of those files at the same time (by selecting them both in the same folder)

### Current Results

The files are incorrectly detected as Excel files, which obviously fails.

<!-- What results occurred or were shown. -->

### Expected Behavior

They should be detected as text files (which indeed happens when selecting only one file)

### Screenshots

![image](https://github.com/user-attachments/assets/7b44966a-355e-48bc-abe7-008a24380ac0)


### Versions<!--  (please complete the following information)-->
 - Operating System: Debian testing
 - JRE or JDK Version: 19
 - OpenRefine: 3.9-SNAPSHOT

### Additional context
Observed at Wikimania 2024

### Additional contract requirements

- When several files are uploaded together in one import, each uploaded file's entry in the import's retrieval result must report its detected format in its `format` field, the same way it does when a single file is uploaded.
- When the uploaded files are text files of the same kind, each file's reported format must start with `text`, and the format offered for the import as a whole must also start with `text`.
- When the uploaded files are non-text spreadsheet files (for example `.xls` files), the format offered for the import as a whole must not start with `text`.
