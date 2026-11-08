bool in bpf code becomes u8 in generated skeleton code
Hi,

The current skel generation does this. I was looking up how to convert the bool properly to u8 when I found [this](https://stackoverflow.com/a/47705543/2277013) . Any thoughts on why the skel generation represents bool in C as u8 in Rust? Also, how would you convert rust bool to rust u8 so that the bool value does get passed to bpf code?

Thanks in advance

### Additional contract requirements

- When generating Rust definitions from BTF, represent a C `bool` field as Rust `bool` (for example, emit `pub d: bool,` for a `bool d;` field).
