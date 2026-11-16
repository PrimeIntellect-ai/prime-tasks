Version 0.10 places Copy value literals behind a reference where 0.9 did not
I have a large collection of templates that compiles perfectly fine with version 0.9 of askama, but when I try to upgrade to 0.10, I get a bunch of type errors because a bunch of `Copy` types that were previously passed as values now get placed behind a reference
