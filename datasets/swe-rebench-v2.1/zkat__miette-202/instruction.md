Indentation with tabs throws off labels
(Sorry to not provide a proper repro. I’ll provide one later if you want, just wanted to get the issue opened before I forget).

If I have code indented with tabs, it seems that something goes wrong with the labelled spans:
```ts
function lol(): void {
	const x: i32 = 1;
};
```

<img width="522" alt="Screenshot 2021-10-10 at 14 35 29" src="https://user-images.githubusercontent.com/234957/136698061-2f7787cb-4d4b-4af3-9426-9599131bffea.png">

If I instead indent the code with spaces, it looks correct:

<img width="533" alt="Screenshot 2021-10-10 at 14 35 35" src="https://user-images.githubusercontent.com/234957/136698070-f6dbe452-5a47-4e78-a5c5-48a76398ad49.png">

I’m assuming that this might be due to terminal configuration how to display tabs?

### Additional contract requirements

When the graphical report handler renders a source line, tab characters are
replaced by spaces so that the cursor advances to the next tab stop rather than
by a fixed width. A tab encountered at visual column `c` is rendered as
`tab_width - (c % tab_width)` spaces, where `tab_width` is the configured tab
width (set through `GraphicalReportHandler::tab_width`). Label underlines and
label connectors are positioned using these visual columns, so a label on a line
that contains tabs stays aligned with the highlighted source text.
