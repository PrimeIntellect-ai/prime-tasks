Allow length(array) in addition to length(string)
Apparently length() can't be called with an array argument currently. If I'm not mistaken, that's POSIX behaviour. Though, various other `awk`s support it. The following program:

	BEGIN {
		split("abc", a, "")
		for (i=1; i<=length(a); i++) {
			print a[i]
		}
		exit
	}

, run with `goawk`, will print `parse error: can't use array "a" as scalar`. As I noticed, I can work around it using `n = split(...`. So perhaps in this case it is not much of a problem, but I opened the issue nonetheless, just in case this isn't intended.
