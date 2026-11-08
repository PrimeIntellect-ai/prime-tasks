Piping into another command - inshellisense does not work on that other command
**Is your feature request related to a problem? Please describe.**
I want to use Inshellisense on multiple commands when constructing more complex command line invocations that use pipes. For example
```
ls | cat -
```
should bring up the options for the `cat` command. But I don't get any options, just a list of filenames, which is useless, as I am piping into `cat` and don't need to supply a filename.


**Describe the solution you'd like**
```
ls | cat -
```
should bring up the options for the `cat` command

### Additional contract requirements

- Suggestions are produced for the command that follows the last pipe in the input, not for the command before it. For example, `ls | cat -` must produce the same suggestions as typing `cat -` on its own (the options for `cat`), instead of the filename suggestions for `ls`.
