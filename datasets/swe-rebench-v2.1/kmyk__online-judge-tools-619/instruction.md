download: no samples found in AtCoder tenka1_2014_qualA_e
`oj d` fails for <https://atcoder.jp/contests/tenka1-2014-quala/tasks/tenka1_2014_qualA_b> and <https://atcoder.jp/contests/tenka1-2014-quala/tasks/tenka1_2014_qualA_e> without making corrupted files.

嘘を出力するわけではないのであまり深刻ではないが、AtCoder 側の JavaScript はきちんと認識しているのでたぶん直せるし直しておくべき

``` console
$ oj d https://atcoder.jp/contests/tenka1-2014-quala/tasks/tenka1_2014_qualA_e       [x] problem recognized: AtCoderProblem.from_url('https://atcoder.jp/contests/tenka1-2014-quala/tasks/tenka1_2014_qualA_e'): https://atcoder.jp/contests/tenka1-2014-quala/tasks/tenka1_2014_qualA_e
[x] load cookie from: /home/ubuntu/.local/share/online-judge-tools/cookie.jar
[x] GET: https://atcoder.jp/contests/tenka1-2014-quala/tasks/tenka1_2014_qualA_e
[x] 200 OK
[x] save cookie to: /home/ubuntu/.local/share/online-judge-tools/cookie.jar
[x] append history to: /home/ubuntu/.cache/online-judge-tools/download-history.jsonl
```
