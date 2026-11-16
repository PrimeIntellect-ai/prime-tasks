File copy strategy of `goc build` needs to be optimized
Some files like `unix socket` is not allowed to be copied. When project files contians these file, `goc build .` will return an error. The file copy strategy needs optimize.
