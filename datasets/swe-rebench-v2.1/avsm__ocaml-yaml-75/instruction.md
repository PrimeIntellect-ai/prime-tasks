Probably a memory corruption when serializing a large yaml value
Encountered presumably a memory corruption while serializing relatively large
yaml value on yaml-3.1.0.

To reproduce I have this code

```
let rec yaml_of_yojson_value = function
  | `Null -> `Null
  | `Bool a -> `Bool a
  | `Float a -> `Float a
  | `String a -> `String a
  | `Int a -> `Float (Float.of_int a)
  | `Intlit a -> `String a
  | `Tuple a
  | `List a -> `A (List.map yaml_of_yojson_value a)
  | `Assoc a -> `O (List.map (fun (k, v) -> k, yaml_of_yojson_value v) a)
  | `Variant (a, None) -> `String a
  | `Variant (a, Some v) -> `O [a, yaml_of_yojson_value v]

let die message =
  prerr_endline message;
  exit 1

let rec iter path =
  let yojson = Yojson.Safe.from_file path in
  let yaml = yaml_of_yojson_value yojson in
  match Yaml.to_string yaml with
  | Error (`Msg error) -> die error
  | Ok s ->
      (* Sometimes program doesn't crash but produces corrupted YAML string *)
      match String.index_opt s '\000' with
      | Some _ -> die "broken"
      | None -> iter path

let () = iter Sys.argv.(1)
```

Compiled on OCaml-4.14.0 with dune (3.9.1) using this `dune`:
```
(executable
  (name yaml_crash)
  (libraries yojson yaml))
```

Sometimes output is corrupted and sometimes I get this:
```
Program received signal SIGSEGV, Segmentation fault.
(gdb) bt
#0  __memmove_sse2_unaligned_erms ()
    at ../sysdeps/x86_64/multiarch/memmove-vec-unaligned-erms.S:675
#1  0x00005555556d90bb in memcpy (__len=14633, __src=<optimized out>,
    __dest=<optimized out>) at /usr/include/bits/string_fortified.h:29
#2  yaml_string_write_handler (data=0x5555558faaa0, buffer=<optimized out>,
    size=14633) at api.c:435
#3  0x00005555556ef0b9 in yaml_emitter_flush (emitter=emitter@entry=0x5555558faaa0)
    at writer.c:53
#4  0x00005555556e1745 in yaml_emitter_emit_document_end (event=0x555555813388,
    emitter=0x5555558faaa0) at emitter.c:721
#5  yaml_emitter_state_machine (event=0x555555813388, emitter=0x5555558faaa0)
    at emitter.c:441
#6  yaml_emitter_emit (emitter=0x5555558faaa0, event=<optimized out>) at emitter.c:291
#7  0x00005555556d8cf9 in yaml_stub_17_yaml_emitter_emit (x89=<optimized out>,
    x88=<optimized out>) at yaml_stubs.c:123
#8  0x0000555555635276 in camlYaml_ffi__G__fun_1261 () at ffi/lib/g.ml:241
#9  0x000055555562fa36 in camlYaml__Stream__fun_2131 () at lib/stream.ml:293
#10 0x0000555555632207 in camlYaml__fun_2124 () at lib/yaml.ml:115
#11 0x000055555562e133 in camlDune__exe__Yaml_crash__iter_428 () at yaml_crash.ml:21
#12 0x000055555562e216 in camlDune__exe__Yaml_crash__entry () at yaml_crash.ml:28
#13 0x000055555562af49 in caml_program ()
#14 0x0000555555714ec5 in caml_start_program ()
#15 0x000055555571526f in caml_startup_common ()
#16 0x00005555557152b9 in caml_startup ()
#17 0x000055555562a93c in main ()
```

I couldn't find minimal input that causes corruption but I managed to reproduce
it on 'obfuscated' [data](http://ix.io/4Cm1).

Don't know if it's relevant but ctypes version is 0.20.2.
