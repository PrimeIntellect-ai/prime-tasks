Can generics parameter be used as actual parameter of generics?
Currently, generics parameter can't be used as actual parameter.
But I think generics parameter can resolve in this context.
Is this a bug, or intended behaviour?

```sv
module ModuleA::<TOP_PARAM: const> {
    struct STRUCT_TYPE::<WIDTH: const> {
        value: logic<WIDTH>,
    }
    var s1: STRUCT_TYPE::<32>       ; // ok
    var s2: STRUCT_TYPE::<TOP_PARAM>; // ng
}

module Top{
 inst a: ModuleA::<32>;
}
```
```
  💥 "TOP_PARAM" is expected to "enum or union or struct", but it is "generic
  │ parameter"
   ╭─[:6:27]
 5 │     var s1: STRUCT_TYPE::<32>       ; // ok
 6 │     var s2: STRUCT_TYPE::<TOP_PARAM>; // ng
   ·                           ────┬────
   ·                               ╰── Error location
 7 │ }
   ╰────
```

docs says
> Additionally, the actual parameters should be accessible at the position of the generics declaration. For example, module names can be used as actual parameters because it is accessible through the whole project. On the other hand, local parameters can’t be used as actual parameters in many cases. This is caused by that the local parameters is not accessible from the potision of the generics declaration.
>
> さらに、実パラメータはジェネリクス定義位置から参照できなければなりません。例えば、モジュール名はプロジェクト全体から参照できるので、実パラメータとして使用できます。一方、ローカルパラメータは多くの場合、実パラメータとして使用できません。これはローカルパラメータがジェネリクス定義位置からは参照できない場合に発生します。
