Expose compilerlib library publicly?
I am working on some proprietary code generator for [Twirp](https://twitchtv.github.io/twirp/docs/intro.html) and was able to implement it successfully using this protobuf implementation for OCaml, but I had to vendor the library and mark `compilerlib` as a public library to be able to do so. Would be nice if compiler library was public, it's quite useful for developing protobuf related tooling.

### Additional contract requirements

- The compiler library must be publicly available under the Dune library name `ocaml-protoc.compiler-lib` and expose the wrapper module `Ocaml_protoc_compiler_lib`.
