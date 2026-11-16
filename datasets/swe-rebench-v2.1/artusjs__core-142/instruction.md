[RFC] 移除 app.getContainer，规范 Container 获取途径
目前通过 ctx/app 形式获取 Container 的形式是不统一的（`app.getContainer()` / `ctx.container`），希望做出如下统一：

- 对于 ctx/app 上的取值统一为 `container` 属性（即 `ctx.container` / `app.container`）
  - 对于用户的 set 行为（`ctx.container = xxx`）归类为不当使用，后期考虑通过 getter/setter
- 对于经过 IoC 管理的类，统一通过 Inject 完成取值，代码如下：

```ts
// a_singleton_clazz.ts
import { Injectable, Inject, Container } from '@artus/injection';

@Injectable()
export default class MyClazz {
  @Inject()
  container: Container; // Supported by #139
}

// a_execution_clazz.ts
import { Injectable, Inject, Container, ScopeEnum } from '@artus/injection';

@Injectable({
  scope: ScopeEnum.Execution
})
export default class MyClazz {
  @Inject()
  executionContainer: ExecutionContainer; // Will support
}
```
