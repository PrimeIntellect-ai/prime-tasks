Remove suspend lambda parameter with CoroutineScope receiver rule
> There is no clear answer yet which uses [of marking suspend CoroutineScope.() -> Unit] have to be prohibited and which shouldn't

https://youtrack.jetbrains.com/issue/KT-52042/Clarifying-suspend-lambda-and-function-with-coroutineScope-as-pa#focus=Comments-27-6029021.0-0
So I would revert marking the lambda parameter too and focus on `suspend fun CoroutineScope.foo` only.

_Originally posted by @hfhbd in https://github.com/detekt/detekt/issues/4616#issuecomment-1106242397_
