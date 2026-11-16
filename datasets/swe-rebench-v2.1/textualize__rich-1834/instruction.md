Remove lru_cache from methods
Using lru_cache on a method may cause Python to hold on to references (via self) for longer than strictly necessary.

We should review instances of lru_cache decorator in Rich, and if affected we might want to replace them with the LRUCache object.

It may not be a huge problem since I think must uses of lru_cache set a sensible maximum size.

### Additional contract requirements

- Add a public function `_get_pulse_segments(fore_style: Style, back_style: Style, color_system: str, no_color: bool, ascii: bool = False) -> List[Segment]` in module `rich.progress_bar`.


- When called as `_get_pulse_segments(Style.parse("red"), Style.parse("yellow"), None, False, False)`, the function must return a list of 20 segments: ten `Segment("━", Style.parse("red"))` segments followed by ten `Segment("━", Style.parse("yellow"))` segments.
