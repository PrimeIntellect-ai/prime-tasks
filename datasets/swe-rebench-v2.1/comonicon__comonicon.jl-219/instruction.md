Casting `print` seems to break `--help` and `--version` flags
If I want to `@cast` the `print` function, it seems to be overloaded when I am running commands with `--help` and `--version` flags. Here I add the following lines to [FakePkg.jl](https://github.com/comonicon/Comonicon.jl/blob/master/example/FakePkg/src/FakePkg.jl#L6):

```julia
@cast function print(file)
    @show file
    if splitext(file)[2] == ".toml"
        print("hhhh")
    else
        # An intentional error
        error("my casted `print` is loaded!")
    end
end
```

and simplify Comonicon.toml to

```toml
name = "pkg"

[install]
completion=true
quiet=false
compile="min"
optimize=2

[download]
host="github.com"
user="Roger-luo"
repo="Foo.jl"
```

and install the command `pkg`.

And when I run `pkg --help` or `pkg --version`, they throw the error:

```shell
❯ pkg --help
file = "\n\n\e[94m\e[1m  pkg\e[22m\e[39m v0.1.0\n\n\n\n\e[0m\e[1mUsage\e[22m\n\n  \e[94m\e[1mpkg\e[22m\e[39m\e[94m <command>\e[39m\n\n\e[0m\e[1mCommands\e[22m\n\n  \e[94m\e[1madd\e[22m\e[39m                                                       fake add\n\n  \e[94m\e[1mprint\e[22m\e[39m\n\n  \e[94m\e[1mnoarguments\e[22m\e[39m                                               fake noarguments\n\n  \e[94m\e[1mrm\e[22m\e[39m                                                        fake rm\n\n  \e[94m\e[1mregistry\e[22m\e[39m                                                  fake registry\n\n  \e[94m\e[1mactivate\e[22m\e[39m                                                  fake activate\n\n\n\n\e[0m\e[1mFlags\e[22m\n\n\e[96m  -h, --help\e[39m                                                Print this help message\n\e[96m  -V, --version\e[39m                                             Print version\n"
ERROR: LoadError: my casted `print` is loaded!
Stacktrace:
 [1] error(s::String)
   @ Base ./error.jl:33
 [2] print(file::String)
   @ FakePkg ~/Comonicon.jl/example/FakePkg/src/FakePkg.jl:13
 [3] command_main(ARGS::Vector{String})
   @ FakePkg ~/.julia/packages/Comonicon/RerN0/src/codegen/julia.jl:136
 [4] command_main()
   @ FakePkg ~/.julia/packages/Comonicon/RerN0/src/codegen/julia.jl:88
 [5] top-level scope
   @ ~/.julia/bin/pkg:14
in expression starting at ~/.julia/bin/pkg:14
```

```shell
❯ pkg --version
file = v"0.1.0"
ERROR: LoadError: MethodError: no method matching splitext(::VersionNumber)
Closest candidates are:
  splitext(::String) at ~/.julia/juliaup/julia-1.7.3+0.x64/share/julia/base/path.jl:207
  splitext(::AbstractString) at ~/.julia/juliaup/julia-1.7.3+0.x64/share/julia/base/path.jl:577
Stacktrace:
 [1] print(file::VersionNumber)
   @ FakePkg ~/Comonicon.jl/example/FakePkg/src/FakePkg.jl:9
 [2] command_main(ARGS::Vector{String})
   @ FakePkg ~/.julia/packages/Comonicon/RerN0/src/codegen/julia.jl:99
 [3] command_main()
   @ FakePkg ~/.julia/packages/Comonicon/RerN0/src/codegen/julia.jl:88
 [4] top-level scope
   @ ~/.julia/bin/pkg:14
in expression starting at ~/.julia/bin/pkg:14
```

```shell
❯ pkg print Project.toml
file = "Project.toml"
file = "hhhh"
ERROR: LoadError: my casted `print` is loaded!
Stacktrace:
 [1] error(s::String)
   @ Base ./error.jl:33
 [2] print(file::String)
   @ FakePkg ~/Comonicon.jl/example/FakePkg/src/FakePkg.jl:13
 [3] print(file::String)
   @ FakePkg ~/.ghq/github.com/comonicon/Comonicon.jl/example/FakePkg/src/FakePkg.jl:10
 [4] command_main(ARGS::Vector{String})
   @ FakePkg ~/.julia/packages/Comonicon/RerN0/src/codegen/julia.jl:322
 [5] command_main()
   @ FakePkg ~/.julia/packages/Comonicon/RerN0/src/codegen/julia.jl:88
 [6] top-level scope
   @ ~/.julia/bin/pkg:14
in expression starting at ~/.julia/bin/pkg:14
```

However, if I rename `print` to `show`, e.g., the above error disappears:

```julia
@cast function show(file)
    @show file
    if splitext(file)[2] == ".toml"
        print("hhhh")
    else
        # An intentional error
        error("my casted `print` is loaded!")
    end
end
```

```shell
❯ pkg show Project.toml
file = "Project.toml"
hhhh

❯ pkg --version
0.1.0%

❯ pkg --help


  pkg v0.1.0



Usage

  pkg <command>

Commands

  add                                                       fake add

  rm                                                        fake rm

  show

  noarguments                                               fake noarguments

  registry                                                  fake registry

  activate                                                  fake activate



Flags

  -h, --help                                                Print this help message
  -V, --version                                             Print version
```

**Version of the package:**
run `Pkg.status()` under your environment that uses `Comonicon`

```julia
julia> Pkg.status()
     Project FakePkg v0.1.0
      Status `~/Comonicon.jl/example/FakePkg/Project.toml`
  [863f3e99] Comonicon v0.12.17
  [ff7dd447] FromFile v0.1.5
  [14b8a8f1] PkgTemplates v0.7.29
  [8dfed614] Test
```
