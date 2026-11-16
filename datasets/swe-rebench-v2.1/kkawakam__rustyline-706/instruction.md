Crash at rustyline-11.0.0/src/keymap.rs:205:18
Hi,

when I have rustyline configured the following way:


```
 let config_builder = rustyline::config::Config::builder()
  .max_history_size(10000)?
  .history_ignore_dups( true)?
  .auto_add_history(true)
  .bell_style(rustyline::config::BellStyle::None)
  .completion_type(rustyline::config::CompletionType::List)
  .edit_mode( rustyline::EditMode::Vi);

 let config = config_builder.build();

```

(note that vi mode is active)

Later on I am in the commandline via:

`rl.readline(">> ");`

And I press 'ESC' (so I am in the command mode of the vi mode)
and then I press '.' then it crashes.

`>> thread 'main' panicked at 'internal error: entered unreachable code', .../.cargo/registry/src/github.com-1ecc6299db9ec823/rustyline-11.0.0/src/keymap.rs:205:18`

'.' in the vi mode is the repetition of the latest command but in this situation there was no latest command yet.

Regards,
Frank Schwidom
