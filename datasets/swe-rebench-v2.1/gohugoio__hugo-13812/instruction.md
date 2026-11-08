panic: recovered from errgroup.Group: assignment to entry in nil map
Up until v0.147.1 the build concludes with no issues, anything above that will present this error. I have tried troubleshooting but the error message doesn't quite make the culprit clear to me.

Tested on Void Linux and Alpine Linux.

- [Reference repository](https://git.sr.ht/~cujo/cujo.casa)
- [Failed build output](https://builds.sr.ht/~cujo/job/1514474)

```
Start building sites …
hugo v0.147.7+extended linux/amd64 BuildDate=unknown

Total in 38 ms
panic: recovered from errgroup.Group: assignment to entry in nil map

goroutine 1 [running]:
golang.org/x/sync/errgroup.(*Group).Wait(0xc000880d80)
	/builddir/hugo-0.147.7/_build-hugo-xbps/pkg/mod/golang.org/x/sync@v0.14.0/errgroup/errgroup.go:70 +0x6d
github.com/gohugoio/hugo/hugolib.(*HugoSites).assemble(0xc00040cdc0, {0x249ed10, 0x3741c80}, {0x24a7250?, 0xc00007fe60?}, 0xc0005d6c80)
	/builddir/hugo-0.147.7/hugolib/hugo_sites_build.go:307 +0x40f
github.com/gohugoio/hugo/hugolib.(*HugoSites).Build.func4(...)
	/builddir/hugo-0.147.7/hugolib/hugo_sites_build.go:152
github.com/gohugoio/hugo/hugolib.(*HugoSites).Build(0xc00040cdc0, {0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0}, {0x0, ...})
	/builddir/hugo-0.147.7/hugolib/hugo_sites_build.go:159 +0x74a
github.com/gohugoio/hugo/commands.(*hugoBuilder).buildSites(0xc0000dc0c0?, 0x0)
	/builddir/hugo-0.147.7/commands/hugobuilder.go:425 +0x10d
github.com/gohugoio/hugo/commands.(*hugoBuilder).fullBuild.func3(...)
	/builddir/hugo-0.147.7/commands/hugobuilder.go:542
github.com/gohugoio/hugo/commands.(*hugoBuilder).fullBuild(0xc000144f00, 0x0)
	/builddir/hugo-0.147.7/commands/hugobuilder.go:558 +0x3f2
github.com/gohugoio/hugo/commands.(*hugoBuilder).build(0xc000144f00)
	/builddir/hugo-0.147.7/commands/hugobuilder.go:397 +0x65
github.com/gohugoio/hugo/commands.(*rootCommand).Run.func1(0xc000144f00?, 0xc000641540?)
	/builddir/hugo-0.147.7/commands/commandeer.go:382 +0x86
github.com/gohugoio/hugo/commands.(*rootCommand).Run(0xc000231080, {0x0?, 0x0?}, 0xc000641540, {0x31f9ea854ea5a7e6?, 0xc0004c7a20?, 0x0?})
	/builddir/hugo-0.147.7/commands/commandeer.go:387 +0x134
github.com/bep/simplecobra.(*Commandeer).compile.func1(0xc0001c0f00?, {0x3741c80?, 0x4?, 0x1f64b04?})
	/builddir/hugo-0.147.7/_build-hugo-xbps/pkg/mod/github.com/bep/simplecobra@v0.6.0/simplecobra.go:113 +0x4c
github.com/spf13/cobra.(*Command).execute(0xc00013f508, {0xc00003e110, 0x0, 0x0})
	/builddir/hugo-0.147.7/_build-hugo-xbps/pkg/mod/github.com/spf13/cobra@v1.9.1/command.go:1015 +0xaaa
github.com/spf13/cobra.(*Command).ExecuteC(0xc00013f508)
	/builddir/hugo-0.147.7/_build-hugo-xbps/pkg/mod/github.com/spf13/cobra@v1.9.1/command.go:1148 +0x46f
github.com/spf13/cobra.(*Command).ExecuteContextC(...)
	/builddir/hugo-0.147.7/_build-hugo-xbps/pkg/mod/github.com/spf13/cobra@v1.9.1/command.go:1080
github.com/bep/simplecobra.(*Exec).Execute(0xc00006ecb8, {0x249ed10?, 0x3741c80?}, {0xc00003e110?, 0xc000002301?, 0xc00006a688?})
	/builddir/hugo-0.147.7/_build-hugo-xbps/pkg/mod/github.com/bep/simplecobra@v0.6.0/simplecobra.go:155 +0xd4
github.com/gohugoio/hugo/commands.Execute({0xc00003e110, 0x0, 0x0})
	/builddir/hugo-0.147.7/commands/commandeer.go:68 +0x2f3
main.main()
	/builddir/hugo-0.147.7/main.go:25 +0x56
```

### What version of Hugo are you using (`hugo version`)?

<pre>
$ hugo version
hugo v0.147.7+extended linux/amd64 BuildDate=unknown
</pre>

### Does this issue reproduce with the latest release?

Yes
