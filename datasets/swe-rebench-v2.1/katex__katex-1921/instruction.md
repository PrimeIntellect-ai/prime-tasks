Support \textup
`\textup{text}` renders text that is always upright (i.e. not italicised), regardless of its content.

### Additional contract requirements

- Also support `\textmd{text}`: rendering `\textmd{R}` and `\textbf{\textmd{R}}` must include `<span class="mord textmd">R</span>`, and rendering `\textmd{\textbf{R}}` must include `<span class="mord textbf">R</span>`.
- Rendering `\textup{R}` and `\textit{\textup{R}}` must include `<span class="mord textup">R</span>`.
