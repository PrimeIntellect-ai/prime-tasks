Request: report "redefinition of the built-in" errors for function related variables
**Is your feature request related to a problem? Please describe.**

Currently, function related variables are not checked by `redefinition of the built-in ...`.
It would be nice if revive reports `redefinition of the built-in ...` errors for function related variables.

For example, revive does not report any errors for the following `main.go` file:
```golang
// This is a package comment
package main

func main() {
}

// 1 param
func foo1(new int) {
	_ = new
}

// 2 result
func foo2() (new int) {
	return
}

// 3 type param
func foo3[new any]() {
}
```

```
❯ revive -set_exit_status main.go

❯ echo $?
0
```

**Describe the solution you'd like**

revive reports `redefinition of the built-in ...` errors for function related variables, so that:

```
❯ revive -set_exit_status main.go
main.go:8:11: redefinition of the built-in function new
main.go:13:14: redefinition of the built-in function new
main.go:18:11: redefinition of the built-in function new

❯ echo $?
1
```

**Describe alternatives you've considered**

NA

**Additional context**

I'm not completely certain, but I believe that by making the following changes, this feature can be implemented.

```diff
diff --git rule/redefines-builtin-id.go rule/redefines-builtin-id.go
index b3ff084..d0870fd 100644
--- rule/redefines-builtin-id.go
+++ rule/redefines-builtin-id.go
@@ -125,6 +125,29 @@ func (w *lintRedefinesBuiltinID) Visit(node ast.Node) ast.Visitor {
 		if ok, bt := w.isBuiltIn(id); ok {
 			w.addFailure(n, fmt.Sprintf("redefinition of the built-in %s %s", bt, id))
 		}
[HIDDEN]
 	case *ast.AssignStmt:
 		for _, e := range n.Lhs {
 			id, ok := e.(*ast.Ident)
```

### Additional contract requirements

- Report a “redefinition of the built-in …” error when a function parameter, named result, or type parameter shadows a built-in identifier. For example, each of these declarations using `new` should produce `redefinition of the built-in function new`.
