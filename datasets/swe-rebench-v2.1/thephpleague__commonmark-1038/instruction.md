lineStart in Table Extension does not yield the correct line
### Version(s) affected

"2.4.2"

### Description

Using the Table extension, the Table node does not report the correct startLine.

### How to reproduce

```

## Tabelle

| Datum | Programm | Ort |
| --- | --- | --- |
| 22. Mai | Anreise | Eichberg |
| 23. Mai | Programm | Eichberg |
| 24. Mai | Programm | Eichberg |
| 25. Mai | Programm | Eichberg |
```

startLine should be 4 but is 5
endLine should be 9 it is 9

Node after parsing is:

![2024-07-23 at 14 59 20_CleanShot_IntelliJ IDEA@2x](https://github.com/user-attachments/assets/96da3415-f281-4b1b-a7c0-43df7dd488d8)



### Possible solution

As of now I work around it in my renderer by subtracting 1 from the start line

### Additional context

_No response_

### Did this project help you today? Did it make you happy in any way?

oh yes ! it is a great project which helps to get full control over the Markdown processing
