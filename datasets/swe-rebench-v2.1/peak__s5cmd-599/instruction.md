Flatten list?
I see you have `--flatten` with `cp` but it seems like it's not supported for `ls`?

I might be able to do a pull request to add this, it would be really useful for deeply nested directories (not my idea to store the data this way, I just get paid to clean it up).

### Additional contract requirements

- For `ls`, provide a `--show-fullpath` mode that renders each listed object as its full S3 URL, including the complete key path, instead of the standard formatted listing.
