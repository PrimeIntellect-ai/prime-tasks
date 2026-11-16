File name parsing fails for file names with spaces
I recently encountered a patch containing this file deletion (paths sanitized):

```
diff --git a/path/to/file/File with Spaces.pdf b/path/to/file/File with Spaces.pdf
deleted file mode 100644
index 6e02dcd4fabc172009aca3a6f78763246c59b8fe..0000000000000000000000000000000000000000
```

I think I assumed these would be quoted, but Git does not seem to consider spaces special characters when generating patches. This leads to a `git file header: missing filename information` error.

Check behavior against `git_header_name` in `apply.c` to see how Git handles this.
