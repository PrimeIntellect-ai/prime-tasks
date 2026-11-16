Errors in editable builds are noisy, creating friction
For editable builds, if a part of the build fails, setuptools emits hundreds of lines of traceback and messaging that obscures the inner cause (such as a compile error). This extra context is useless to the developer who knows that there are problems with their project and are repeatedly invoking the backend `build_editable` hook in order to enact the compile and troubleshoot changes.

> However, I find that even bypassing all of the packaging context, the bulk of the output is still all coming from Setuptools, and only 7 lines are saved.
>
> ```
>  pyobjc-core master 🐚 git diff
> diff --git a/pyobjc-core/Modules/objc/block_support.m b/pyobjc-core/Modules/objc/block_support.m
> index 86bdd3597..0b2acd9eb 100644
> --- a/pyobjc-core/Modules/objc/block_support.m
> +++ b/pyobjc-core/Modules/objc/block_support.m
> @@ -36,7 +36,7 @@ static Class gGlobalBlockClass = nil;
>  static Class gStackBlockClass = nil;
>
>  struct block_descriptor {
> -    unsigned long int reserved;
> +    unsignd long int reserved;
>      unsigned long int size;
>      void (*copy_helper)(void* dst, void* src);
>      void (*dispose_helper)(void* src);
>  pyobjc-core master 🐚 py -3.13 -m pip-run setuptools wheel -- -c 'import setuptools.build_meta as backend; backend.build_editable(wheel_directory="throwaway")' 2>1 | tail -n 120
> clang -fno-strict-overflow -Wsign-compare -Wunreachable-code -fno-common -dynamic -DNDEBUG -g -O3 -Wall -I/opt/homebrew/opt/python@3.13/Frameworks/Python.framework/Versions/3.13/include/python3.13 -c Modules/objc/OC_PythonDate.m -o /var/folders/f2/2plv6q2n7l932m2x004jlw340000gn/T/tmp9lh3j9d2.build-temp/Modules/objc/OC_PythonDate.o -g -fexceptions -fno-objc-arc -Wall -Wno-variadic-macros -Wstrict-prototypes -Wbad-function-cast -Wmissing-prototypes -Wformat=2 -W -Wpointer-arith -Wmissing-declarations -Wnested-externs -W -Wno-import -Wno-unknown-pragmas -Wshorten-64-to-32 -Werror -Wno-cast-function-type-mismatch -I/usr/include/ffi -fvisibility=hidden -g -UNDEBUG -isysroot /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk -DPyObjC_BUILD_RELEASE=1504
> clang -fno-strict-overflow -Wsign-compare -Wunreachable-code -fno-common -dynamic -DNDEBUG -g -O3 -Wall -I/opt/homebrew/opt/python@3.13/Frameworks/Python.framework/Versions/3.13/include/python3.13 -c Modules/objc/OC_PythonDictionary.m -o /var/folders/f2/2plv6q2n7l932m2x004jlw340000gn/T/tmp9lh3j9d2.build-temp/Modules/objc/OC_PythonDictionary.o -g -fexceptions -fno-objc-arc -Wall -Wno-variadic-macros -Wstrict-prototypes -Wbad-function-cast -Wmissing-prototypes -Wformat=2 -W -Wpointer-arith -Wmissing-declarations -Wnested-externs -W -Wno-import -Wno-unknown-pragmas -Wshorten-64-to-32 -Werror -Wno-cast-function-type-mismatch -I/usr/include/ffi -fvisibility=hidden -g -UNDEBUG -isysroot /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk -DPyObjC_BUILD_RELEASE=1504
> clang -fno-strict-overflow -Wsign-compare -Wunreachable-code -fno-common -dynamic -DNDEBUG -g -O3 -Wall -I/opt/homebrew/opt/python@3.13/Frameworks/Python.framework/Versions/3.13/include/python3.13 -c Modules/objc/OC_PythonEnumerator.m -o /var/folders/f2/2plv6q2n7l932m2x004jlw340000gn/T/tmp9lh3j9d2.build-temp/Modules/objc/OC_PythonEnumerator.o -g -fexceptions -fno-objc-arc -Wall -Wno-variadic-macros -Wstrict-prototypes -Wbad-function-cast -Wmissing-prototypes -Wformat=2 -W -Wpointer-arith -Wmissing-declarations -Wnested-externs -W -Wno-import -Wno-unknown-pragmas -Wshorten-64-to-32 -Werror -Wno-cast-function-type-mismatch -I/usr/include/ffi -fvisibility=hidden -g -UNDEBUG -isysroot /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk -DPyObjC_BUILD_RELEASE=1504
> clang -fno-strict-overflow -Wsign-compare -Wunreachable-code -fno-common -dynamic -DNDEBUG -g -O3 -Wall -I/opt/homebrew/opt/python@3.13/Frameworks/Python.framework/Versions/3.13/include/python3.13 -c Modules/objc/OC_PythonNumber.m -o /var/folders/f2/2plv6q2n7l932m2x004jlw340000gn/T/tmp9lh3j9d2.build-temp/Modules/objc/OC_PythonNumber.o -g -fexceptions -fno-objc-arc -Wall -Wno-variadic-macros -Wstrict-prototypes -Wbad-function-cast -Wmissing-prototypes -Wformat=2 -W -Wpointer-arith -Wmissing-declarations -Wnested-externs -W -Wno-import -Wno-unknown-pragmas -Wshorten-64-to-32 -Werror -Wno-cast-function-type-mismatch -I/usr/include/ffi -fvisibility=hidden -g -UNDEBUG -isysroot /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk -DPyObjC_BUILD_RELEASE=1504
> clang -fno-strict-overflow -Wsign-compare -Wunreachable-code -fno-common -dynamic -DNDEBUG -g -O3 -Wall -I/opt/homebrew/opt/python@3.13/Frameworks/Python.framework/Versions/3.13/include/python3.13 -c Modules/objc/OC_PythonObject.m -o /var/folders/f2/2plv6q2n7l932m2x004jlw340000gn/T/tmp9lh3j9d2.build-temp/Modules/objc/OC_PythonObject.o -g -fexceptions -fno-objc-arc -Wall -Wno-variadic-macros -Wstrict-prototypes -Wbad-function-cast -Wmissing-prototypes -Wformat=2 -W -Wpointer-arith -Wmissing-declarations -Wnested-externs -W -Wno-import -Wno-unknown-pragmas -Wshorten-64-to-32 -Werror -Wno-cast-function-type-mismatch -I/usr/include/ffi -fvisibility=hidden -g -UNDEBUG -isysroot /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk -DPyObjC_BUILD_RELEASE=1504
> clang -fno-strict-overflow -Wsign-compare -Wunreachable-code -fno-common -dynamic -DNDEBUG -g -O3 -Wall -I/opt/homebrew/opt/python@3.13/Frameworks/Python.framework/Versions/3.13/include/python3.13 -c Modules/objc/OC_PythonSet.m -o /var/folders/f2/2plv6q2n7l932m2x004jlw340000gn/T/tmp9lh3j9d2.build-temp/Modules/objc/OC_PythonSet.o -g -fexceptions -fno-objc-arc -Wall -Wno-variadic-macros -Wstrict-prototypes -Wbad-function-cast -Wmissing-prototypes -Wformat=2 -W -Wpointer-arith -Wmissing-declarations -Wnested-externs -W -Wno-import -Wno-unknown-pragmas -Wshorten-64-to-32 -Werror -Wno-cast-function-type-mismatch -I/usr/include/ffi -fvisibility=hidden -g -UNDEBUG -isysroot /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk -DPyObjC_BUILD_RELEASE=1504
> clang -fno-strict-overflow -Wsign-compare -Wunreachable-code -fno-common -dynamic -DNDEBUG -g -O3 -Wall -I/opt/homebrew/opt/python@3.13/Frameworks/Python.framework/Versions/3.13/include/python3.13 -c Modules/objc/OC_PythonURL.m -o /var/folders/f2/2plv6q2n7l932m2x004jlw340000gn/T/tmp9lh3j9d2.build-temp/Modules/objc/OC_PythonURL.o -g -fexceptions -fno-objc-arc -Wall -Wno-variadic-macros -Wstrict-prototypes -Wbad-function-cast -Wmissing-prototypes -Wformat=2 -W -Wpointer-arith -Wmissing-declarations -Wnested-externs -W -Wno-import -Wno-unknown-pragmas -Wshorten-64-to-32 -Werror -Wno-cast-function-type-mismatch -I/usr/include/ffi -fvisibility=hidden -g -UNDEBUG -isysroot /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk -DPyObjC_BUILD_RELEASE=1504
> clang -fno-strict-overflow -Wsign-compare -Wunreachable-code -fno-common -dynamic -DNDEBUG -g -O3 -Wall -I/opt/homebrew/opt/python@3.13/Frameworks/Python.framework/Versions/3.13/include/python3.13 -c Modules/objc/OC_PythonUnicode.m -o /var/folders/f2/2plv6q2n7l932m2x004jlw340000gn/T/tmp9lh3j9d2.build-temp/Modules/objc/OC_PythonUnicode.o -g -fexceptions -fno-objc-arc -Wall -Wno-variadic-macros -Wstrict-prototypes -Wbad-function-cast -Wmissing-prototypes -Wformat=2 -W -Wpointer-arith -Wmissing-declarations -Wnested-externs -W -Wno-import -Wno-unknown-pragmas -Wshorten-64-to-32 -Werror -Wno-cast-function-type-mismatch -I/usr/include/ffi -fvisibility=hidden -g -UNDEBUG -isysroot /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk -DPyObjC_BUILD_RELEASE=1504
> clang -fno-strict-overflow -Wsign-compare -Wunreachable-code -fno-common -dynamic -DNDEBUG -g -O3 -Wall -I/opt/homebrew/opt/python@3.13/Frameworks/Python.framework/Versions/3.13/include/python3.13 -c Modules/objc/ObjCPointer.m -o /var/folders/f2/2plv6q2n7l932m2x004jlw340000gn/T/tmp9lh3j9d2.build-temp/Modules/objc/ObjCPointer.o -g -fexceptions -fno-objc-arc -Wall -Wno-variadic-macros -Wstrict-prototypes -Wbad-function-cast -Wmissing-prototypes -Wformat=2 -W -Wpointer-arith -Wmissing-declarations -Wnested-externs -W -Wno-import -Wno-unknown-pragmas -Wshorten-64-to-32 -Werror -Wno-cast-function-type-mismatch -I/usr/include/ffi -fvisibility=hidden -g -UNDEBUG -isysroot /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk -DPyObjC_BUILD_RELEASE=1504
> clang -fno-strict-overflow -Wsign-compare -Wunreachable-code -fno-common -dynamic -DNDEBUG -g -O3 -Wall -I/opt/homebrew/opt/python@3.13/Frameworks/Python.framework/Versions/3.13/include/python3.13 -c Modules/objc/block_support.m -o /var/folders/f2/2plv6q2n7l932m2x004jlw340000gn/T/tmp9lh3j9d2.build-temp/Modules/objc/block_support.o -g -fexceptions -fno-objc-arc -Wall -Wno-variadic-macros -Wstrict-prototypes -Wbad-function-cast -Wmissing-prototypes -Wformat=2 -W -Wpointer-arith -Wmissing-declarations -Wnested-externs -W -Wno-import -Wno-unknown-pragmas -Wshorten-64-to-32 -Werror -Wno-cast-function-type-mismatch -I/usr/include/ffi -fvisibility=hidden -g -UNDEBUG -isysroot /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk -DPyObjC_BUILD_RELEASE=1504
> Modules/objc/block_support.m:39:5: error: unknown type name 'unsignd'; did you mean 'unsigned'?
>    39 |     unsignd long int reserved;
>       |     ^~~~~~~
>       |     unsigned
> 1 error generated.
> Traceback (most recent call last):
>   File "/var/folders/f2/2plv6q2n7l932m2x004jlw340000gn/T/pip-run-j166v718/setuptools/_distutils/spawn.py", line 87, in spawn
>     subprocess.check_call(cmd, env=_inject_macos_ver(env))
>     ~~~~~~~~~~~~~~~~~~~~~^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
>   File "/opt/homebrew/Cellar/python@3.13/3.13.3/Frameworks/Python.framework/Versions/3.13/lib/python3.13/subprocess.py", line 419, in check_call
>     raise CalledProcessError(retcode, cmd)
> subprocess.CalledProcessError: Command '['/usr/bin/clang', '-fno-strict-overflow', '-Wsign-compare', '-Wunreachable-code', '-fno-common', '-dynamic', '-DNDEBUG', '-g', '-O3', '-Wall', '-I/opt/homebrew/opt/python@3.13/Frameworks/Python.framework/Versions/3.13/include/python3.13', '-c', 'Modules/objc/block_support.m', '-o', '/var/folders/f2/2plv6q2n7l932m2x004jlw340000gn/T/tmp9lh3j9d2.build-temp/Modules/objc/block_support.o', '-g', '-fexceptions', '-fno-objc-arc', '-Wall', '-Wno-variadic-macros', '-Wstrict-prototypes', '-Wbad-function-cast', '-Wmissing-prototypes', '-Wformat=2', '-W', '-Wpointer-arith', '-Wmissing-declarations', '-Wnested-externs', '-W', '-Wno-import', '-Wno-unknown-pragmas', '-Wshorten-64-to-32', '-Werror', '-Wno-cast-function-type-mismatch', '-I/usr/include/ffi', '-fvisibility=hidden', '-g', '-UNDEBUG', '-isysroot', '/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk', '-DPyObjC_BUILD_RELEASE=1504']' returned non-zero exit status 1.
>
> The above exception was the direct cause of the following exception:
>
> Traceback (most recent call last):
>   File "/var/folders/f2/2plv6q2n7l932m2x004jlw340000gn/T/pip-run-j166v718/setuptools/_distutils/compilers/C/unix.py", line 221, in _compile
>     self.spawn(compiler_so + cc_args + [src, '-o', obj] + extra_postargs)
>     ~~~~~~~~~~^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
>   File "/var/folders/f2/2plv6q2n7l932m2x004jlw340000gn/T/pip-run-j166v718/setuptools/_distutils/compilers/C/base.py", line 1158, in spawn
>     spawn(cmd, dry_run=self.dry_run, **kwargs)
>     ~~~~~^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
>   File "/var/folders/f2/2plv6q2n7l932m2x004jlw340000gn/T/pip-run-j166v718/setuptools/_distutils/spawn.py", line 93, in spawn
>     raise DistutilsExecError(
>         f"command {_debug(cmd)!r} failed with exit code {err.returncode}"
>     ) from err
> distutils.errors.DistutilsExecError: command '/usr/bin/clang' failed with exit code 1
>
> During handling of the above exception, another exception occurred:
>
> Traceback (most recent call last):
>   File "/var/folders/f2/2plv6q2n7l932m2x004jlw340000gn/T/pip-run-j166v718/setuptools/command/editable_wheel.py", line 139, in run
>     self._create_wheel_file(bdist_wheel)
>     ~~~~~~~~~~~~~~~~~~~~~~~^^^^^^^^^^^^^
>   File "/var/folders/f2/2plv6q2n7l932m2x004jlw340000gn/T/pip-run-j166v718/setuptools/command/editable_wheel.py", line 345, in _create_wheel_file
>     files, mapping = self._run_build_commands(dist_name, unpacked, lib, tmp)
>                      ~~~~~~~~~~~~~~~~~~~~~~~~^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
>   File "/var/folders/f2/2plv6q2n7l932m2x004jlw340000gn/T/pip-run-j166v718/setuptools/command/editable_wheel.py", line 268, in _run_build_commands
>     self._run_build_subcommands()
>     ~~~~~~~~~~~~~~~~~~~~~~~~~~~^^
>   File "/var/folders/f2/2plv6q2n7l932m2x004jlw340000gn/T/pip-run-j166v718/setuptools/command/editable_wheel.py", line 295, in _run_build_subcommands
>     self.run_command(name)
>     ~~~~~~~~~~~~~~~~^^^^^^
>   File "/var/folders/f2/2plv6q2n7l932m2x004jlw340000gn/T/pip-run-j166v718/setuptools/_distutils/cmd.py", line 357, in run_command
>     self.distribution.run_command(command)
>     ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~^^^^^^^^^
>   File "/var/folders/f2/2plv6q2n7l932m2x004jlw340000gn/T/pip-run-j166v718/setuptools/dist.py", line 1106, in run_command
>     super().run_command(command)
>     ~~~~~~~~~~~~~~~~~~~^^^^^^^^^
>   File "/var/folders/f2/2plv6q2n7l932m2x004jlw340000gn/T/pip-run-j166v718/setuptools/_distutils/dist.py", line 1021, in run_command
>     cmd_obj.run()
>     ~~~~~~~~~~~^^
>   File "<string>", line 669, in run
>   File "/var/folders/f2/2plv6q2n7l932m2x004jlw340000gn/T/pip-run-j166v718/setuptools/command/build_ext.py", line 99, in run
>     _build_ext.run(self)
>     ~~~~~~~~~~~~~~^^^^^^
>   File "/var/folders/f2/2plv6q2n7l932m2x004jlw340000gn/T/pip-run-j166v718/setuptools/_distutils/command/build_ext.py", line 368, in run
>     self.build_extensions()
>     ~~~~~~~~~~~~~~~~~~~~~^^
>   File "/var/folders/f2/2plv6q2n7l932m2x004jlw340000gn/T/pip-run-j166v718/setuptools/_distutils/command/build_ext.py", line 484, in build_extensions
>     self._build_extensions_serial()
>     ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~^^
>   File "/var/folders/f2/2plv6q2n7l932m2x004jlw340000gn/T/pip-run-j166v718/setuptools/_distutils/command/build_ext.py", line 510, in _build_extensions_serial
>     self.build_extension(ext)
>     ~~~~~~~~~~~~~~~~~~~~^^^^^
>   File "/var/folders/f2/2plv6q2n7l932m2x004jlw340000gn/T/pip-run-j166v718/setuptools/command/build_ext.py", line 264, in build_extension
>     _build_ext.build_extension(self, ext)
>     ~~~~~~~~~~~~~~~~~~~~~~~~~~^^^^^^^^^^^
>   File "/var/folders/f2/2plv6q2n7l932m2x004jlw340000gn/T/pip-run-j166v718/setuptools/_distutils/command/build_ext.py", line 565, in build_extension
>     objects = self.compiler.compile(
>         sources,
>     ...<5 lines>...
>         depends=ext.depends,
>     )
>   File "/var/folders/f2/2plv6q2n7l932m2x004jlw340000gn/T/pip-run-j166v718/setuptools/_distutils/compilers/C/base.py", line 655, in compile
>     self._compile(obj, src, ext, cc_args, extra_postargs, pp_opts)
>     ~~~~~~~~~~~~~^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
>   File "/var/folders/f2/2plv6q2n7l932m2x004jlw340000gn/T/pip-run-j166v718/setuptools/_distutils/compilers/C/unix.py", line 223, in _compile
>     raise CompileError(msg)
> distutils.compilers.C.errors.CompileError: command '/usr/bin/clang' failed with exit code 1
> /var/folders/f2/2plv6q2n7l932m2x004jlw340000gn/T/pip-run-j166v718/setuptools/_distutils/dist.py:1021: _DebuggingTips: Problem in editable installation.
> !!
>
>         ********************************************************************************
>         An error happened while installing `pyobjc-core` in editable mode.
>
>         The following steps are recommended to help debug this problem:
>
>         - Try to install the project normally, without using the editable mode.
>           Does the error still persist?
>           (If it does, try fixing the problem before attempting the editable mode).
>         - If you are using binary extensions, make sure you have all OS-level
>           dependencies installed (e.g. compilers, toolchains, binary libraries, ...).
>         - Try the latest version of setuptools (maybe the error was already fixed).
>         - If you (or your project dependencies) are using any setuptools extension
>           or customization, make sure they support the editable mode.
>
>         After following the steps above, if the problem still persists and
>         you think this is related to how setuptools handles editable installations,
>         please submit a reproducible example
>         (see https://stackoverflow.com/help/minimal-reproducible-example) to:
>
>             https://github.com/pypa/setuptools/issues
>
>         See https://setuptools.pypa.io/en/latest/userguide/development_mode.html for details.
>         ********************************************************************************
>
> !!
>   cmd_obj.run()
> error: command '/usr/bin/clang' failed with exit code 1
> ```
>
> At this point, I agree, the output from setuptools is too verbose and unhelpful. It may have been more helpful when setuptools was being defensive about rolling out the PEP 660 hooks, but at this stage, it should revert to assuming that it's doing the right thing and should be less verbose about how it arrived at a compile error.

Instead, Setuptools should start to assume that it's the user's fault if the build is failing and give them that context and not the internal details about how the build failed within Setuptools.

 _Originally posted by @jaraco in [#497](https://github.com/ronaldoussoren/pyobjc/issues/497#issuecomment-2855905245)_

### Additional contract requirements

- On an editable-wheel build failure, the exception's `__notes__` must include a note containing the literal `debugging-tips`.
