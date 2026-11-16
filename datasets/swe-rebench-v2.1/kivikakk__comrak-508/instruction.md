The parsing of front matter may not be correct
It seems that markdown with only front matter without a newline at the end may not be parsed correctly.

## Incorrect case

source:

```rust
let text = "---
foo: bar
---";
let arena = Arena::new();
let mut options = Options::default();
options.extension.front_matter_delimiter = Some("---".to_owned());
let ast = parse_document(&arena, text, &options);
println!("{:?}", ast);
```

output:

```
Node {
  data: RefCell { value: Ast { value: Document, sourcepos: Sourcepos { start: LineColumn { line: 1, column: 1 }, end: LineColumn { line: 3, column: 3 } }, internal_offset: 0, content: "", open: false, last_line_blank: false, table_visited: false, line_offsets: [] } },
  children: [
    Node { data: RefCell { value: Ast { value: ThematicBreak, sourcepos: Sourcepos { start: LineColumn { line: 1, column: 1 }, end: LineColumn { line: 1, column: 3 } }, internal_offset: 0, content: "", open: false, last_line_blank: false, table_visited: false, line_offsets: [] } }, children: [] },
    Node { data: RefCell { value: Ast { value: Heading(NodeHeading { level: 2, setext: true }), sourcepos: Sourcepos { start: LineColumn { line: 2, column: 1 }, end: LineColumn { line: 3, column: 3 } }, internal_offset: 0, content: "foo: bar\n", open: false, last_line_blank: false, table_visited: false, line_offsets: [0] } }, children: [Node { data: RefCell { value: Ast { value: Text("foo: bar"), sourcepos: Sourcepos { start: LineColumn { line: 2, column: 1 }, end: LineColumn { line: 2, column: 8 } }, internal_offset: 0, content: "", open: false, last_line_blank: false, table_visited: false, line_offsets: [] } }, children: [] }] }
  ]
}
```

## Correct case

source:

```rust
let text = "---
foo: bar
---
";
let arena = Arena::new();
let mut options = Options::default();
options.extension.front_matter_delimiter = Some("---".to_owned());
let ast = parse_document(&arena, text, &options);
println!("{:?}", ast);
```

output:

```
Node {
  data: RefCell { value: Ast { value: Document, sourcepos: Sourcepos { start: LineColumn { line: 1, column: 1 }, end: LineColumn { line: 0, column: 0 } }, internal_offset: 0, content: "", open: false, last_line_blank: false, table_visited: false, line_offsets: [] } },
  children: [
    Node { data: RefCell { value: Ast { value: FrontMatter("---\nfoo: bar\n---\n"), sourcepos: Sourcepos { start: LineColumn { line: 0, column: 1 }, end: LineColumn { line: 0, column: 0 } }, internal_offset: 0, content: "", open: false, last_line_blank: false, table_visited: false, line_offsets: [] } }, children: [] }
  ]
}
```

## Environment

* rustc 1.83.0 (90b35a623 2024-11-26)
* comrak 0.31.0

Thanks for a great library ❤️
