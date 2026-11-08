when a struct has more than one kind of empty slice whose type is pointer ,decode will panic
<!-- Please use this template while reporting a bug and provide as much info as possible. Not doing so may result in your bug not being addressed in a timely manner. Thanks!

-->


**What happened**:
1.在同一个结构体里面有两种不同的指针切片的时候，如果切片两个都赋值为空切片，反序列化的时候会造成Panic。
2.在同一个结构体里面有两种不同的结构切片的时候，如果切片两个都赋值为空切片，反序列化后两个切片都会赋值为nil。
下面这段代码能复现这个结果
**What you expected to happen**:
1.反序列化回来两个空切片
2.反序列化回来两个空切片
**How to reproduce it (as minimally and precisely as possible)**:

import (
	hessian "github.com/apache/dubbo-go-hessian2"
)

func init() {
	hessian.RegisterPOJO(new(SpPoint))
	hessian.RegisterPOJO(new(Point))
	hessian.RegisterPOJO(new(ReqInfo))
	hessian.RegisterPOJO(new(ReqInfo2))
}

type SpPoint struct {
	X  int
	Y  int
	Sp int
}

func (SpPoint) JavaClassName() string {
	return "com.test.SpPoint"
}

type ReqInfo struct {
	Name     string
	SpPoints []*SpPoint
	Points   []*Point
}

type ReqInfo2 struct {
	Name     string
	SpPoints []SpPoint
	Points   []Point
}

func (ReqInfo2) JavaClassName() string {
	return "com.test.ReqInfo2"
}

func (ReqInfo) JavaClassName() string {
	return "com.test.ReqInfo"
}

func main() {
	d := ReqInfo{
		Name:     "test",
		SpPoints: []*SpPoint{},
		Points:   []*Point{},
	}
	//d := ReqInfo2{
	//	Name:     "test",
	//	SpPoints: []SpPoint{},
	//	Points:   []Point{},
	//}

	encoder := hessian.NewEncoder()
	err := encoder.Encode(d)
	if err != nil {
		return
	}
	decoder := hessian.NewDecoder(encoder.Buffer())
	doInterface, err := decoder.Decode()

	_ = doInterface
}

**Anything else we need to know?**:
