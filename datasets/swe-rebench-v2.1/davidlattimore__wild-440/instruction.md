Tried to write dynamic symbol definition without a resolution
Error:
```
  Running command: "make libs" in dir: /home/mateusz/projects/rust-rdkafka/target/debug/build/rdkafka-sys-e3110b4b51e6f8c5/out
  Error: Failed copying from <epilogue> to output file

  Caused by:
      Tried to write dynamic symbol definition without a resolution: symbol `_ZTv0_n56_N7RdKafka10HandleImpl8outq_lenEv` (1257 local=239) in file #1536 (6/0) (ProducerImpl.o) defined as 566 in file #1024 (4/0) (HandleImpl.o) (ADDRESS)
  collect2: error: ld returned 255 exit status
```

Reproduction:
```
jj git clone https://github.com/fede1024/rust-rdkafka

cd rust-rdkafka

PATH=~/projects/wild:$PATH cargo b
```
It doesn't reproduce by changing `~/.cargo/config.toml` like in the README because `[target.<triple>]` doesn't apply when linking build scripts.

### Additional contract requirements

- When linking `libc-integration.c`, the duplicate weak definitions of `weak_fn3` must resolve so that `weak_fn3()` returns `15`.
