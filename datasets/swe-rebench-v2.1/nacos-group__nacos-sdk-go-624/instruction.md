PublishConfig 不支持传递修改人
如标题，PublishConfig 的参数中没有修改人字段，而 nacos api 里有 src_user 参数，可传递修改人。

我们内部使用的 nacos 并不需要登录，也不使用 nacos 原生控台，二开的 控台可同时管理多个 nacos 集群，这是背景。

以前，我们通过 http 接口和 nacos server 交互，最近准备用 golang，发现 golang 的sdk PublishConfig 没有 src_user 字段，期望添加。

### Additional contract requirements

The parameters accepted by `PublishConfig` expose a caller-settable `SrcUser` field for the modifying user. When supplied, its value is sent to Nacos as the `src_user` publish-request parameter.
