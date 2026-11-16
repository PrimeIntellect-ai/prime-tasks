Add an ability to open direct location
**Is your feature request related to a problem? Please describe.**
I usually deal with direct location output from the compiler which is a path to the file plus the location marker. e.g.

```
my/directory/file.rs:24:4
```

**Describe the solution you'd like**
I want to be able to paste this directly to the telescope, press enter, and appear in the direct symbol location.

> P.S. This is possible in vs code with no additional setup for example

**Describe alternatives you've considered**
1. Open telescope search
2. Observe nothing found
3. Remove paths
4. type :24<CR> to go to the line

**Additional context**
This should be primarily an input feature — strip out everything that looks like location, search, and when open file focus specific symbol. That's why I think it should be a part of the telescope core and not be solved via plugins.

If you are interested I can open PR for this

### Additional contract requirements

- Add a public function `__separate_file_path_location(path)` in module `telescope.utils`. It takes a file path string that may end with a `:line` and optional `:column` location suffix and returns the file path with the location suffix removed, the line number, and the column number. The line and column are integers, and each is `0` when it is absent or not a number.

- In file-search pickers, entering a file path with a `:line` and optional `:column` suffix searches for the file without that suffix and opens the selected file at the requested location.
