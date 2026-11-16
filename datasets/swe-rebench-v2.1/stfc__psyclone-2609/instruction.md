Support parallelism clause on `ACC routine` directive.
![image](https://github.com/stfc/PSyclone/assets/17409212/49e941f5-3e49-4ace-9d7f-36c26076acd4)
where
![image](https://github.com/stfc/PSyclone/assets/17409212/35e39116-c40f-4b4a-b400-573d053c6f83)
This issue will allow `gang`, `worker` or `vector` to be specified when creating the directive.

### Additional contract requirements

`ACCRoutineDirective` creation must accept a `parallelism` argument that selects `gang`, `worker`, or `vector`, and the generated directive text must include the selected level. `ACCRoutineTrans.apply` must accept the same selection through `options={"parallelism": level}` and use it in the directive it creates. The transformation must reject an unsupported parallelism value and applying it repeatedly must not add duplicate ACC routine directives.
