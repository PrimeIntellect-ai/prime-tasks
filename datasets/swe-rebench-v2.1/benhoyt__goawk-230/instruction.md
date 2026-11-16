{} behaves like 1, END{} doesn't exhaust input
See:
```
$ seq 3 | goawk '{}'
1
2
3
$ seq 3 | { goawk 'END{}'; wc -l;}
3
```
According to POSIX the first command shouldn't print anything, and the second should print 0.
