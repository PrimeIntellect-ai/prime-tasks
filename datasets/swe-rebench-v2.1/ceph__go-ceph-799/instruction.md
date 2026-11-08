undefined: AllocHintFlags
Trying to build a simple "list images" but getting the following every time I attempt to build it:
`../go/pkg/mod/github.com/ceph/go-ceph@v0.19.0/rados/ioctx_set_alloc_hint.go:24:114: undefined: AllocHintFlags
../go/pkg/mod/github.com/ceph/go-ceph@v0.19.0/rados/write_op_set_alloc_hint.go:19:96: undefined: AllocHintFlags`

What am I doing wrong here?

Got the latest pacific libraries and trying to build with: `go build -tags pacific`

Here is an example:
```
package main

import (
	"bytes"
	"fmt"
	"io/ioutil"

	"github.com/ceph/go-ceph/rados"
	"github.com/ceph/go-ceph/rbd"
)

var (
	c, _    = rados.NewConnWithUser("admin")
	cephCfg = "/etc/ceph/ceph.conf"
	pools   = []string{"vms", "images"}
)

func getImageList(pool string) {
	conn, err := newRadosConn()
	if err != nil {
		return nil, err
	}
	defer conn.Shutdown()

	ioctx, err := conn.OpenIOContext(pool)
	if err != nil {
		return nil, err
	}
	defer ioCtx.Destroy()

	return rbd.GetImageNames(ioctx)
}

func newRadosConn() (*rados.Conn, error) {
	conn, err := rados.NewConnWithUser(user)
	if err != nil {
		return nil, fmt.Errorf("error creating rados connection: %s", err)
	}

	err = conn.ReadConfigFile(cephCfg)
	if err != nil {
		return nil, fmt.Errorf("error reading config file: %s", err)
	}

	err = conn.Connect()
	if err != nil {
		return nil, fmt.Errorf("error connecting to rados: %s", err)
	}

	return conn, nil
}

func main() {
	for _, pool := range pools {
		imageList, err := getImageList(pool)
		if err != nil {
			fmt.Printf("failed to get %s's image list", pool)
			continue
		}

		for _, image := range imageList {
			fmt.Printf("pool: %s, image: %s ", pool, image)
	}
}
```
