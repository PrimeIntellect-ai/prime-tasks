Node#moveTo was deprecated. Use [HIDDEN].
Using 2.3.0.

### Additional contract requirements

- When combining duplicate selectors, produce these exact serialized outputs:
- For `.a {color: black; height: 10px} .a {background-color: red; width: 20px}`, output `.a {color: black; height: 10px;background-color: red; width: 20px}`.
- When removing duplicate properties, for `.a {height: 10px; color: black;} .a {color: blue; width: 20px;}`, output `.a {height: 10px;color: blue; width: 20px;}`.
- When retaining duplicate properties, for `.a {height: 10px; color: black;} .a {color: blue; width: 20px;}`, output `.a {height: 10px; color: black;color: blue; width: 20px;}`.
- When processing duplicate selectors, do not emit a deprecation warning about `Node#moveTo`.
- When combining duplicate rules, move declarations into the retained rule using `Container#append`, not the deprecated `Node#moveTo`.
