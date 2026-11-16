Panic with a decode hook to convert a `time.Time` in a struct into a `*github.com/golang/protobuf/types.Timestamp` in other struct
I was trying to use mapstructure to convert between a protobuf type and a corresponding internal type. The two times had different forms of timestamp where the protobuf type used the well known Timestamp type and the internal type used a `time.Time`.

My decode hook looked like the following:

```
var (
	tsType      = reflect.TypeOf((*types.Timestamp)(nil))
	timePtrType = reflect.TypeOf((*time.Time)(nil))
	timeType    = timePtrType.Elem()
	mapStrInf   = reflect.TypeOf((map[string]interface{})(nil))
)

// HookTimeToPBtimestamp is a mapstructure decode hook to translate a time.Time value to
// a protobuf Timestamp value.
func HookTimeToPBTimestamp(from, to reflect.Type, data interface{}) (interface{}, error) {
	// Note that mapstructure doesn't do direct struct to struct conversion in this case. I
	// still don't completely understand why converting the PB TS to time.Time does but
	// I suspect it has something to do with the struct containing a concrete time.Time
	// as opposed to a pointer to a time.Time. Regardless this path through mapstructure
	// first will decode the concrete time.Time into a map[string]interface{} before
	// eventually decoding that map[string]interface{} into the *types.Timestamp. One
	// other note is that mapstructure ends up creating a new Value and sets it it to
	// the time.Time value and thats what gets passed to us. That is why we end up
	// seeing a *time.Time instead of a time.Time.
	if from == timePtrType && to == mapStrInf {
		ts := data.(*time.Time)
		nanos := ts.UnixNano()

		seconds := nanos / 1000000000
		nanos = nanos % 1000000000

		return &map[string]interface{}{
			"Seconds": seconds,
			"Nanos":   int32(nanos),
		}, nil
	}
	return data, nil
}
```

I had a test to ensure my decode hook was working but it was panicing like so:

```panic: reflect: reflect.flag.mustBeAssignable using unaddressable value [recovered]
        panic: reflect: reflect.flag.mustBeAssignable using unaddressable value

goroutine 4 [running]:
testing.tRunner.func1.1(0x14b6d00, 0xc000061410)
        /usr/local/go/src/testing/testing.go:941 +0x3d0
testing.tRunner.func1(0xc00012f440)
        /usr/local/go/src/testing/testing.go:944 +0x3f9
panic(0x14b6d00, 0xc000061410)
        /usr/local/go/src/runtime/panic.go:967 +0x166
reflect.flag.mustBeAssignableSlow(0x15)
        /usr/local/go/src/reflect/value.go:247 +0x138
reflect.flag.mustBeAssignable(...)
        /usr/local/go/src/reflect/value.go:234
reflect.Value.Set(0x14d9fe0, 0xc00007bd10, 0x15, 0x14d9fe0, 0xc00007bd70, 0x15)
        /usr/local/go/src/reflect/value.go:1526 +0x3b
github.com/mitchellh/mapstructure.(*Decoder).decodeMapFromMap(0xc000010070, 0x1481f3b, 0x9, 0x14d9fe0, 0xc000010098, 0x195, 0x14d9fe0, 0xc00007bd10, 0x15, 0x14d9fe0, ...)
        /Users/mkeeler/Code/repos/mapstructure/mapstructure.go:843 +0x49c
github.com/mitchellh/mapstructure.(*Decoder).decodeMap(0xc000010070, 0x1481f3b, 0x9, 0x14a7320, 0xc000010098, 0x14d9fe0, 0xc00007bd10, 0x15, 0x14a7320, 0xc000010098)
        /Users/mkeeler/Code/repos/mapstructure/mapstructure.go:763 +0x56a
github.com/mitchellh/mapstructure.(*Decoder).decode(0xc000010070, 0x1481f3b, 0x9, 0x1552700, 0xc00000e600, 0x14d9fe0, 0xc00007bd10, 0x15, 0x0, 0x0)
        /Users/mkeeler/Code/repos/mapstructure/mapstructure.go:439 +0x625
github.com/mitchellh/mapstructure.(*Decoder).decodeMapFromStruct(0xc000010070, 0x0, 0x0, 0x14eddc0, 0xc00000e580, 0x99, 0x14d9fe0, 0xc000010078, 0x195, 0x14d9fe0, ...)
        /Users/mkeeler/Code/repos/mapstructure/mapstructure.go:912 +0x978
github.com/mitchellh/mapstructure.(*Decoder).decodeStruct(0xc000010070, 0x0, 0x0, 0x14eddc0, 0xc00000e580, 0x14edd40, 0xc000010068, 0x199, 0x14eddc0, 0xc00000e580)
        /Users/mkeeler/Code/repos/mapstructure/mapstructure.go:1172 +0x329
github.com/mitchellh/mapstructure.(*Decoder).decode(0xc000010070, 0x0, 0x0, 0x14eddc0, 0xc00000e580, 0x14edd40, 0xc000010068, 0x199, 0xc00000e580, 0xc00005df58)
        /Users/mkeeler/Code/repos/mapstructure/mapstructure.go:437 +0x75f
github.com/mitchellh/mapstructure.(*Decoder).Decode(0xc000010070, 0x14eddc0, 0xc00000e580, 0xc00000e580, 0x0)
        /Users/mkeeler/Code/repos/mapstructure/mapstructure.go:370 +0xf0
github.com/hashicorp/consul/agent/agentpb.TestHookTimeToPBTimestamp(0xc00012f440)
        /Users/mkeeler/Code/repos/consul/auto-config/cert-generation/agent/agentpb/translate_test.go:63 +0x16c
```

I managed to find the cause which exists in a couple places. [HIDDEN]

[HIDDEN]

[HIDDEN]

[HIDDEN] I just wanted to have an issue open to track when adding my test to mapstructure_bug_test.go.

### Additional contract requirements

- When a decode hook converts a `time.Time` field during struct-to-struct decoding into a timestamp destination, decoding must complete without a reflection panic, and the destination timestamp must represent the source time, preserving its seconds and nanoseconds.
