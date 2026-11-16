Support empty patches
Hi!

We are using this lib over at https://pr.pico.sh and so far haven't had any issues.  So thank you for your hard work!

We are trying to support cover letters in our patch request workflow, but it looks like since the patch itself is empty, `go-gitdiff` skips over it and returns empty header data.  Ideally this lib would still process the empty patch even if there aren't any diffs in it.

I'm curious what you think about adding support for empty patches?
