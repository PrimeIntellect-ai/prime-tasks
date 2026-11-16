-v must interpret escape sequences
Hi, @benhoyt.

`-v` must interpret escape sequences. I hate this spec of awk, but anyway, reality is what it is. ☹️

```console
$ goawk -v VAR='\t' 'BEGIN{printf VAR}' | hexdump -C
00000000  5c 74                                             |\t|

$ mawk -v VAR='\t' 'BEGIN{printf VAR}' | hexdump -C
00000000  09                                                |.|

$ gawk -v VAR='\t' 'BEGIN{printf VAR}' | hexdump -C
00000000  09                                                |.|
```
