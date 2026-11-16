rebber-plugins: grid-tables stringifier replace \n by \par even in \inlineCode
# markdown

```
+------+----------------------+
| cell | `code                |
|      | with line break`     |
+------+----------------------+
```

# generated latex

```tex
\begin{longtabu}{|p{\dimexpr(\linewidth) / 2}|p{\dimexpr(\linewidth) / 2}|} \hline
\rowfont[c]{\bfseries}
cell & \CodeInline{code \par with line break} \\ \hline
\end{longtabu}
```

# expected latex

```tex
\begin{longtabu}{|p{\dimexpr(\linewidth) / 2}|p{\dimexpr(\linewidth) / 2}|} \hline
\rowfont[c]{\bfseries}
cell & \CodeInline{code with line break} \\ \hline
\end{longtabu}
```

### Additional contract requirements

- In the generated LaTeX, preserve a line break inside inline code as a literal newline character. Do not convert it to `\par` or collapse it to a space.
- For the example, the normative cell content is `\texttt{code\nwith line break}`: the characters `code`, a newline, then `with line break`. This requirement takes precedence over the conflicting space-separated inline-code content shown in the expected LaTeX above.
