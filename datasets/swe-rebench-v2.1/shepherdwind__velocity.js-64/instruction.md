set 命令bug
set变量层级大于2时，后面的set指令会覆盖前面set的值

即形如下面的VM指令

~~~
#set($a.b.c1 = 1 )
#set($a.b.c2 = 2)
~~~

执行后 a = {b:{c2:2}}，c1会被覆盖掉

出错代码：

~~~
var Velocity = require('velocityjs');
var tpl = '#set($a = "{}")\n#set($a.b = "{}")\n#set($a.b.c1 = 1)\n#set($a.b.c2 = 2)\n<h1>$a.b.c1</h1>';
console.log(Velocity.render(tpl, {}));
~~~

原因：
[HIDDEN]

### Additional contract requirements

- When successive `#set` assignments target different leaves beneath a path deeper than two levels, a later assignment must not erase or replace an earlier leaf value.
