unconditional-recursive warn where no any reasone
**Describe the bug**
Show warning where is no any reasone

**To Reproduce**

```go

// NewFactory - создает фабрику калькуляций
func NewFactory(options ICalculationFactoryOptions) *Factory {
	return &Factory{factoryOptions: options}
}

var defaultFactory = NewFactory(DefaultFactoryOptions())
```

Will warn about `unconditional-recursive` - where is no any reasone to do it
