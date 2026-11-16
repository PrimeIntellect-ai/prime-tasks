Terminate my application with exit code
Bug report from #1073

### Discussed in https://github.com/uber-go/fx/discussions/1073

<div type='discussions-op-text'>

<sup>Originally posted by **nemliyartym** April 28, 2023</sup>
Hi all. I would like to know how can I terminate my application with the exit codes I need. I have a simple `smb `module with a run function that calls `shutdowner.Shutdown(fx.ExitCode(20))` with the code I need.

If in main I just call `app.Run()` then my app exits with code 0. Do I test it with `echo$?`. I changed `Run` to call `Start+Done+Stop` to try and get the exit code from `Done`, but that didn't work for me. I also tried to change `Done`to `Wait`, but in this case, the application hangs on the channel of wait.

Please, tell me what am I doing wrong?)

main.go
```go
func main() {
	app := fx.New(
		//fx.NopLogger,
		//config.Module,
		//logger.Module,

		smb.Module,
	)
	//app.Run()

	if err := app.Start(context.TODO()); err != nil {
		fmt.Println(err)
	}

	done := app.Done()
	fmt.Println(done)

	// wait := app.Wait()
	// sig := <-wait
	// fmt.Println(sig.ExitCode)

	if err := app.Stop(context.TODO()); err != nil {
		fmt.Println(err)
	}
}
```
smb.go
```go
type Smb interface {
}

type smb struct {
	logger *zap.Logger
}

func NewSmb(logger *zap.Logger) Smb {
	return &smb{logger: logger}
}

func Run(logger *zap.Logger, shutdowner fx.Shutdowner) error {
	logger.Info("shutdowner")
       //SET EXIT CODE
	shutdowner.Shutdown(fx.ExitCode(20))
	logger.Info("shutdowner2")
	return nil
}

var Module = fx.Module("smb",
	fx.Provide(NewSmb),
	fx.Invoke(Run),
	fx.Decorate(
		func(log *zap.Logger) *zap.Logger {
			return log.Named("smb")
		},
	),
)
```
</div>
