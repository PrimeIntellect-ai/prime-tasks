funcr: handle fmt.Stringer that panics on nil
I ran into this with klog in Kubernetes (see https://github.com/kubernetes/klog/issues/278). While I haven't tested it, funcr is probably also affected, at least here but potentially also elsewhere:
https://github.com/go-logr/logr/blob/99e02a994f50f904b6b201df394776cf687238a9/funcr/funcr.go#L360

The problem is that log calls might pass a nil pointer for a struct which implements `fmt.Stringer`, but then segfaults when called. Here's an example:
https://github.com/kubernetes/kubernetes/blob/a1e8a5bf39d48719dfbcf49ea09223ee04840502/pkg/kubelet/kubelet.go#L2334-L2335

I think it is reasonable to expect that a logging implementation is resilient against such problems. That means that funcr must either check for nil beforehand or deal with the panic. I'm undecided. Perhaps `fmt.Sprintf("%q", <nil stringer>)` can serve as reference.

### Additional contract requirements

- When a nil pointer implementing fmt.Stringer panics on String(), funcr must render `"<panic: value method github.com/go-logr/logr/funcr.Tstringer.String called using nil *Tstringer pointer>"`.
