[BUG] 多环境 Config 合并不正确(v1.0.0-alpha.16)
### 现象

运行时 env 设定失效

### 成因

#131 调整配置合并逻辑为运行时 Object.assign 所有配置文件，这一行为基于 Manifest 中应只包括自身环境的配置文件，`Scanner` 中对此估计不足，现时实现不具备这一效果，导致运行时将全部 Config 合并，造成配置项混乱

### Additional contract requirements

When an environment is selected, runtime configuration must not incorporate settings scoped to other environments.
