Top level `break` instruction causes panic on REPL
The following Goby code from https://github.com/goby-lang/goby/blob/master/vm/statement_test.go#L13 causes panic only on REPL:

```ruby
x = [1, 2, 3]
y = 0
x.each do |i|
  y += i
  if i == 2
    break
  end
end
y
```

```
» y
panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x1 addr=0x68 pc=0x43ef404]

goroutine 1 [running]:
github.com/goby-lang/goby/vm.(*VM).REPLExec(0xc4200a6780, 0xc4201e69c0, 0x5, 0x8)
	/Users/hachi8833/deve/golang/gopath/sys/src/github.com/goby-lang/goby/vm/repl.go:38 +0x4d4
github.com/goby-lang/goby/igb.StartIgb(0x4577c2d, 0x5)
	/Users/hachi8833/deve/golang/gopath/sys/src/github.com/goby-lang/goby/igb/repl.go:231 +0xd23
main.main()
	/Users/hachi8833/deve/golang/gopath/sys/src/github.com/goby-lang/goby/goby.go:29 +0x954
```

Note that the code works fine when running as a file.

And the following works fine on REPL; looks like the bug only occurs on top level `break` instruction.

```ruby
» def foo
¤   x = [1, 2, 3]
¤   y = 0
¤   x.each do |i|
¤     y += i
¤     if i == 2
¤       break
¤     end
¤   end
¤   y
» end
#»
» foo
#» 3
```

FYI: complied with Go 1.9.3.
