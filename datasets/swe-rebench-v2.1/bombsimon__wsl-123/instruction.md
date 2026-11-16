`++`/`--` should be treated as an assignment
Consider this somewhere in the code:
```
	count++
	isSet = true
```
I got this:
```
assignments should only be cuddled with other assignments (wsl)
                        isSet = true
```
but in fact  the count++ is an assignment as well (count = count + 1)
