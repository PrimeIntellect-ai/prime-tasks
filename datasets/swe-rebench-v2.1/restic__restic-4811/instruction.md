Restic restore include-file/exclude-file switches
Output of `restic version`
--------------------------

restic 0.16.4 compiled with go1.21.6 on darwin/amd64


What should restic do differently? Which functionality do you think we should add?
----------------------------------------------------------------------------------

It would be helpful if the include-file, --iinclude-file, --exclude-file, and --iexclude-file switches existed for the "restore" function.


What are you trying to do? What problem would this solve?
---------------------------------------------------------

I recently needed to restore a bunch of different files that got deleted.  About 1600 of them, in random places.  When I did "restic diff" I could easily get a list of all the files that were deleted - but I don't have an easy way to feed that into Restic to restore just those files.

My options are to restore a large swath of files to get a few, or to run restic restore on each file individually - which seems impractical with that many files.


Did restic help you today? Did it make you happy in any way?
------------------------------------------------------------

Restic rules!  ✌️

### Additional contract requirements

The `restore` command must accept the following command line flags, each of
which reads patterns from the named file (one pattern per line):

- `--include-file`
- `--iinclude-file`
- `--exclude-file`
- `--iexclude-file`

Each flag may be given more than once. Patterns read from files are combined
with the patterns given directly through `--include`, `--iinclude`, `--exclude`
and `--iexclude`. When reading a pattern file, blank lines and lines starting
with `#` are ignored, leading and trailing whitespace is removed from each
pattern, environment variables are expanded, and `$$` stands for a literal `$`.
A pattern file that cannot be read, or that contains an invalid pattern, must
make the command fail with an error.
