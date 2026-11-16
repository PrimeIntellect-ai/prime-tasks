use block-based disk usage accounting
We currently use a simple sum of the file sizes of each blob in the cache to estimate the total disk usage. This underestimates the actual disk usage, since most filesystems use 4Kb blocks. We can get a better estimate from the `syscall.Stat_t` struct's `Blocks` field, which is a count of the number of 512 byte blocks used by the file.
