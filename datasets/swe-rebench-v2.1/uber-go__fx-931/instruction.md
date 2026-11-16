onStop executed many times
### Discussed in https://github.com/uber-go/fx/discussions/929

<div type='discussions-op-text'>

<sup>Originally posted by **coolyrat** August 22, 2022</sup>
```go
package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	"go.uber.org/fx"
)

func main() {
	server := fx.New(
		fx.Invoke(func(lc fx.Lifecycle) {
			fmt.Println("first invoke...")
			lc.Append(fx.Hook{
				OnStart: func(ctx context.Context) error {
					fmt.Println("#1 start")
					return nil
				},
				OnStop: func(ctx context.Context) error {
					fmt.Println("#1 stop")
					return nil
				},
			})
		}),

		fx.Invoke(func(lc fx.Lifecycle) {
			fmt.Println("last invoke...")
			lc.Append(fx.Hook{
				OnStart: func(ctx context.Context) error {
					fmt.Println("#2 start")
					return nil
				},
				OnStop: func(ctx context.Context) error {
					fmt.Println("#2 stop")
					return nil
				},
			})
		}),
	)

	go func() {
		server.Run()
	}()

	kill := make(chan os.Signal, 1)
	signal.Notify(kill, syscall.SIGINT, syscall.SIGTERM, syscall.SIGKILL, syscall.SIGQUIT)
	<-kill
	fmt.Println("killed")

	ctx, _ := context.WithTimeout(context.Background(), 10*time.Second)
	if err := server.Stop(ctx); err != nil {
		log.Printf("error stopping gracefully")
	}
}

```

When I give the stop signal, the log
```
...
killed
#2 stop
#1 stop
#2 stop
```

And I am expected to be
```
...
killed
#2 stop
#1 stop
```

Is there anything I'm doing wrong?</div>
