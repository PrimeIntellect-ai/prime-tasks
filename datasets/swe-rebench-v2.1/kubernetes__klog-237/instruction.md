[]byte will use +%v through InfoS.
/kind bug

**What steps did you take and what happened:**
[A clear and concise description of what the bug is.]

```
klog.InfoS("[]byte", "b1", []byte("hello world"))
```
print:
I0508 19:35:13.452661   57319 testKlog.go:11] "[]byte" b1=[104 101 108 108 111 32 119 111 114 108 100]

**What did you expect to happen:**
I0508 19:37:01.473191    2045 testKlog.go:11] "[]byte" b1="hello world"


**Anything else you would like to add:**
[Miscellaneous information that will assist in solving the issue.]
part of https://github.com/kubernetes/kubernetes/issues/101714
As k8s conducts structured log migration, `InfoS `is used more and more, but` []byte`, usually cooperates with %q `before `the migration, is it necessary to submit a PR [HIDDEN]
Currently in InfoS, []byte uses %+v.
https://github.com/kubernetes/klog/blob/0cc9b8363efc89db73313bf618deeff8964c4a86/klog.go#L832
If the idea is approved, I will do it, otherwise I will probably continue to use `klog.InfoS("[]byte", "b1", string([]byte("hello world")))`.
