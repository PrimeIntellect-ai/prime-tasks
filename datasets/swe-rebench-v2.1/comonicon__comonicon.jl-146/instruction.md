in correct markdown flag and argument parsing
When I was doing my MIS emulation CLI on server, the new markdown doc parsing seems not recognizing `-o,--option=<hint>` pattern correctly

### Additional contract requirements

- When parsing an Options item written as `-o, option=<value>`, `split_docstring` must throw an `ErrorException`.
