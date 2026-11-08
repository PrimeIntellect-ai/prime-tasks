Index out of bounds at `firstpass.rs:1424`
I tried running the existing `parse` fuzzer, and found this crash:

```
thread '<unnamed>' panicked at 'index out of bounds: the len is 14 but the index is 14', /home/mg/src/pulldown-cmark/src/firstpass.rs:1424:13
stack backtrace:
   0: rust_begin_unwind
             at /rustc/6bba061467f7c2cab04b262b95eb67bf89265587/library/std/src/panicking.rs:593:5
   1: core::panicking::panic_fmt
             at /rustc/6bba061467f7c2cab04b262b95eb67bf89265587/library/core/src/panicking.rs:67:14
   2: core::panicking::panic_bounds_check
             at /rustc/6bba061467f7c2cab04b262b95eb67bf89265587/library/core/src/panicking.rs:162:5
   3: core::option::Option<T>::map_or
   4: pulldown_cmark::firstpass::scan_paragraph_interrupt
   5: pulldown_cmark::firstpass::FirstPass::parse_paragraph
   6: pulldown_cmark::firstpass::FirstPass::parse_block
   7: pulldown_cmark::firstpass::FirstPass::run
   8: pulldown_cmark::firstpass::run_first_pass
   9: pulldown_cmark::parse::Parser::new_ext
```

The input is a file with a lot of null bytes: [minimized-from-e9832c8a219680362d96eba6a59a76ace4b3cd40.zip](https://github.com/raphlinus/pulldown-cmark/files/11779703/minimized-from-e9832c8a219680362d96eba6a59a76ace4b3cd40.zip).

```
Output of `std::fmt::Debug`:

	FuzzingInput {
	    markdown: ".\r> ^](\r\u{c}\r\0\0\r.\r[^\0\0\\\0\0\0^^^^^]",
	    tables: false,
	    footnotes: true,
	    strikethrough: false,
	    tasklists: true,
	    smart_punctuation: false,
	    heading_attributes: false,
	}
```
