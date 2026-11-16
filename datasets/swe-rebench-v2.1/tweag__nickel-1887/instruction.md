VSCode Extension should not disregard cursor position and collapse all symbol breadcrumbs to "..." in all occasions
**Describe the bug**
The latest version of `nls` provides proper symbol outlines in the "Outlines" Tab. Normally the same symbol information is also displayed as "breadcrumbs" at the top of the editor view, continuing after the file path and scrolls horizontally if the width exceeds the window (below is an example from a rust file in the nickel codebase, powered by rust-analyzer)

![image](https://github.com/tweag/nickel/assets/812576/058d66d7-f24d-4ed4-9da8-6ee240d0467f)

However with a nickel file, all symbol information are collapsed in "..." after the file path (see below, note the cursor is positioned at `_source2`). While one can always click on "..." and navigate to the symbol, IMHO this behavior greatly diminishes the primary utility of breadcrumb that is providing direct visual guidance to the user without keyboard / mouse interaction.

![image](https://github.com/tweag/nickel/assets/812576/871d4f47-6e3c-40a7-8d2d-c771ea622453)

I searched for vscode setting entries and couldn't find a knob that tweaks this behavior.

**To Reproduce**


**Expected behavior**
Expand the symbol information inline in the breadcrumbs bar.

**Environment**
 - OS name + version: NixOS 23.11
 - Version of the code: `nickel-lang-cli nickel 1.5.0 (rev 13ffc85)`

**Additional context**
Add any other context about the problem here.

### Additional contract requirements

- A symbol's selection range must cover its field name, and its full range must extend through the end of its value and any type annotation, without including the comma that follows the field. For example, in `lsp/nls/tests/inputs/symbols-basic.ncl`, `annotated` has selection range `10:2-10:11` and full range `10:2-10:20`.
