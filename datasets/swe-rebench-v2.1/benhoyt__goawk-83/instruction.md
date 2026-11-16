Reconsider handling of bytes vs characters in length() and similar functions
Per @arnoldrobbins comment https://github.com/rmyorston/busybox-w32/issues/174#issuecomment-599194834, the POSIX spec says that `length` and similar functions should work with characters, not bytes. The [POSIX spec](https://pubs.opengroup.org/onlinepubs/9699919799/utilities/awk.html) says:

> The index, length, match, and substr functions should not be confused with similar functions in the ISO C standard; the awk versions deal with characters, while the ISO C standard deals with bytes.

Given that, I wonder why (onetrueawk) `awk`'s `length()` function counts bytes instead of characters, at least by default. Here's output on my macOS Catalina machine:

```
$ echo 絵 | nawk '{print length}'    # onetrueawk/awk 20200228
3
$ echo 絵 | gawk '{print length}'    # gawk 5.0.1
1
$ echo 絵 | mawk '{print length}'    # mawk 1.3.4 2020012
3
$ echo 絵 | goawk '{print length}'    # goawk 1.6.0
3

# for reference:
$ locale
LANG="en_US.UTF-8"
LC_COLLATE="en_US.UTF-8"
LC_CTYPE="en_US.UTF-8"
LC_MESSAGES="en_US.UTF-8"
LC_MONETARY="en_US.UTF-8"
LC_NUMERIC="en_US.UTF-8"
LC_TIME="en_US.UTF-8"
LC_ALL=
```

So I feel good that GoAWK has the majority on its side :-), but as you point out, the `nawk/mawk/goawk/ behavior does seem wrong according to POSIX. What do you recommend, @arnoldrobbins?
