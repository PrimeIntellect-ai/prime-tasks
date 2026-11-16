Replace panicing APIs with such returning errors
This doesn't really affect me, since I only use the APIs that return errors, but it seems to me that it is a bad idea to provide deceptively simple looking functions that panic.
Panicing seems only reasonable if there's a way for the caller to check for simple preconditions that will cause a panic, but here whether `fn from_read` panics or not cannot reasonably be known at the callsite.
