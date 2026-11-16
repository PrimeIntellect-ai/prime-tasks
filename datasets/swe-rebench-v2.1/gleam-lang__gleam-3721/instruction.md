No newline inserted between records inside a const list if the first record spans multiple lines
```gleam
type Command {
  Command(name: String, description: String)
}

const commands = [
  Command(
    name: "dev",
    description: "Start a file watcher that automatically re-compiles your app on all file changes.",
  ), Command(name: "help", description: "Show this help text."),
]
```

when writing the same literal inside a function, the second command will be on its own line ~ :purple_heart:
