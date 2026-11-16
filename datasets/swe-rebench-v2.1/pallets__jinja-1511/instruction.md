Native types for macros
With [native types](https://jinja.palletsprojects.com/en/3.0.x/nativetypes/) we can template out native Python types, which is useful in for example Ansible.

It seems that macros always generate strings though, even in a native environment. Would it be possible to make macros output native types as well, so they are more useful when building up a native data structure?

For (a trivial) example, I would like this to output the integer 5, not the string "[".
```
env.from_string("{%- macro x() -%}{{- [5,6] -}}{%- endmacro -%}{{- x()[0] -}}").render()
```
