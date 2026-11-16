Using tea.Printf before tea.Quit
it is quite difficult to use the `tea.Printf` and `tea.Println` functions right before `tea.Quit`.
When using it with `tea.Batch` and `tea.Quit` for example, there is a race between `tea.Printf` and `tea.Quit`.

Example:

```go
// in this example, we are dealing with a list of tasks,
// display the latest state then start the next task.

  case foo:
     m.current++
     // if there is still work to do
     return m, tea.Batch( // this works fine
       tea.Println(m.tasks[m.current-1].View()),
       m.tasks[m.current].Update(),
     )
     // ...
     // Last element of the list, print it and leave the program
     return m, tea.Batch( // this doesn't work, race between Println and Quit
       tea.Println(m.tasks[m.current-1].View()),
       tea.Quit,
     )
```

By design `tea.Batch` doesn't provide any ordering guarantees, however its use with `tea.Printf` and `tea.Quit` makes it difficult to display *all* messages before quitting the program.

(If I understand correctly, the tea.Print* [example](https://github.com/charmbracelet/bubbletea/blob/master/examples/package-manager/main.go) has the same issue, although it misses the first entry in the list (it's more visible if you deactivate the randomness of the packages function))

I tried with `tea.Sequentially` but it returns the first non-nil message, this ignores the `tea.Quit` message.

Ideally I would like to use `tea.Printf`, then once it's rendered, use `tea.Quit`. Example:

```go
  return m, tea.QuitAfter(tea.Printf("...."))

```

What is the proper way of using `tea.Printf` and then `tea.Quit`?

### Additional contract requirements

- The `tea` package must provide a command constructor `Sequence(cmds ...Cmd) Cmd`. When the returned command runs, the given commands are executed one at a time, in the order they were given: each command starts only after the previous one has returned its message, and the messages are delivered to `Update` in that same order.
- A caller must be able to request printed output and quitting together and have the output rendered before the program exits. For example, `Sequence(Printf("..."), Println("..."), Quit)` must show both printed lines, in the order they were requested, before the program exits.
