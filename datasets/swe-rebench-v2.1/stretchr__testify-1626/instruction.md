Functional Options testing broken for indirect calls
The changes introduced to support testing of functional options (https://github.com/stretchr/testify/pull/1023) are broken with indirect calls.

When the service which exposes the method that supports functional options is injected into another function and invoked, the mock assertions are broken.

The following test and mocks should be supported.

```diff
diff --git a/mock/mock_test.go b/mock/mock_test.go
index 60cf5d0..1c7ca47 100644
--- a/mock/mock_test.go
+++ b/mock/mock_test.go
@@ -20,6 +20,7 @@ import (
 // ExampleInterface represents an example interface.
 type ExampleInterface interface {
 	TheExampleMethod(a, b, c int) (int, error)
+	TheExampleMethodFunctionalOptions(x string, opts ...OptionFn) error
 }

 // TestExampleImplementation is a test implementation of ExampleInterface
@@ -1455,6 +1456,27 @@ func Test_Mock_AssertExpectationsFunctionalOptionsType(t *testing.T) {

 }

+func Test_Mock_AssertExpectationsFunctionalOptionsType_indirect(t *testing.T) {
+
+	indirectFunctionalOptions := func(ei ExampleInterface) {
+		ei.TheExampleMethodFunctionalOptions("testing", OpStr("test"), OpNum(1))
+	}
+
+	var mockedService = new(TestExampleImplementation)
+
+	mockedService.On("TheExampleMethodFunctionalOptions", "testing", FunctionalOptions(OpStr("test"), OpNum(1))).Return(nil).Once()
+
+	tt := new(testing.T)
+	assert.False(t, mockedService.AssertExpectations(tt))
+
+	// make the call now
+	indirectFunctionalOptions(mockedService)
+
+	// now assert expectations
+	assert.True(t, mockedService.AssertExpectations(tt))
+
+}
+
 func Test_Mock_AssertExpectationsFunctionalOptionsType_Empty(t *testing.T) {

 	var mockedService = new(TestExampleImplementation)
```

but instead results in the following error:

```sh
mock: Unexpected Method Call
-----------------------------

TheExampleMethodFunctionalOptions(string,[]mock.OptionFn)
		0: "testing"
		1: []mock.OptionFn{(mock.OptionFn)(0x11a8020), (mock.OptionFn)(0x11a8000)}

The closest call I have is:

TheExampleMethodFunctionalOptions(string,*mock.FunctionalOptionsArgument)
		0: "testing"
		1: []mock.OptionFn{(mock.OptionFn)(0x11a0980), (mock.OptionFn)(0x11a0960)}


Diff: 0: PASS:  (string=testing) == (string=testing)
	1: FAIL:  [mock.Test_Mock_AssertExpectationsFunctionalOptionsType_indirect.func1 mock.Test_Mock_AssertExpectationsFunctionalOptionsType_indirect.func1] != [mock.Test_Mock_AssertExpectationsFunctionalOptionsType_indirect mock.Test_Mock_AssertExpectationsFunctionalOptionsType_indirect]
```

The culprit seems to be the [`funcName`](https://github.com/stretchr/testify/blob/4b2f4d2bcff3848b6a4e63d462da6ce3c21e9c78/mock/mock.go#L1220C1-L1223) call which is used in [`assertOpts`](https://github.com/stretchr/testify/blob/master/mock/mock.go#L1167C1-L1173) returning unexpected values.
