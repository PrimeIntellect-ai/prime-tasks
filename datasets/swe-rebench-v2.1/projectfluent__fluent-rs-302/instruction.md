Improper handling of Windows line feeds in FTL files
Hi, I'm working on porting Fluent.rs to .Net and I stumbled upon a possible error in the parser:

If you try to parse the following string `# msg\r\n# yes\r\n#\r\nfoo=Foo` you'll get errors. The same example on the [Fluent playground](https://www.projectfluent.org/play/), gets you:

```json
{
    "type": "Resource",
    "body": [
        {
            "type": "Message",
            "id": {
                "type": "Identifier",
                "name": "foo",
                "span": {
                    "type": "Span",
                    "start": 14,
                    "end": 17
                }
            },
            "value": {
                "type": "Pattern",
                "elements": [
                    {
                        "type": "TextElement",
                        "value": "Foo",
                        "span": {
                            "type": "Span",
                            "start": 20,
                            "end": 23
                        }
                    }
                ],
                "span": {
                    "type": "Span",
                    "start": 20,
                    "end": 23
                }
            },
            "attributes": [],
            "comment": {
                "type": "Comment",
                "content": "msg\nyes\n",
                "span": {
                    "type": "Span",
                    "start": 0,
                    "end": 13
                }
            },
            "span": {
                "type": "Span",
                "start": 0,
                "end": 23
            }
        }
    ],
    "span": {
        "type": "Span",
        "start": 0,
        "end": 24
    }
}
```


Which makes the most sense. I managed to track down the offending line to this branch:
https://github.com/projectfluent/fluent-rs/blob/4d13b24140409b377362442cf748a7f789c3f822/fluent-syntax/src/parser/comment.rs#L34

If the line was:
```rust
[HIDDEN]
```

I believe the error wouldn't happen, but I haven't tested it.

### Additional contract requirements

- Parsing `# msg\r\n# yes\r\n#\r\nfoo=Foo` should succeed, producing the `foo` message with comment content `msg\nyes\n`.
