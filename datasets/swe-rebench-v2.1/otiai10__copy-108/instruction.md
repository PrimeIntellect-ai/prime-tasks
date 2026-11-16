Add support for embed directories
It would be super useful if this package could copy embed directories.

For example:

Given the following fs tree:

```
/
  /assets
    /foo
       foo.txt
       bar.txt
    hello.txt
    goodbye.txt
  main.go
```

It could use the embed FS to use the copy function.

```golang
//go:embed assets
var assets embed.FS

func foo() error {
  file, err := assets.Open("assets")
  if err != nil {
    return err
  }

  err := Copy(file, "destination")
  if err != nil {
    return err
  }
  return nil
}
```

Or maybe use the Option structure

```golang
opt := Options{
	FS: assets,
}
err := Copy("assets/foo", "new/destination", opt)
```
