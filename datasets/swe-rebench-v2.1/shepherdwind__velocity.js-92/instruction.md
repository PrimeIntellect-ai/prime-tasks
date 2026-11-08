#set 中通过动态的$key给 对象/数组 赋值失败
最近接手的项目中存在类似下面的二次整理数据的代码，在java端解析时可以正常赋值，但是在nodejs端就不行。请问有什么办法可以实现下面的需求，就是用动态的key或index给对象和数组赋值。谢谢:)


<h1>简单赋值</h1>
#set($o = {})

#set($key = "k")
#set($o[$key] = "c")
#set($o.f = "d")
<p>输出 {undefined=c, f=d}</p>

<h1>循环给对象赋值(key)</h1>
#set($obj = {})

#set($objlist = [
  {"k": "a"},
  {"k": "b"},
  {"k": "c"}
])
<p>初始值 obj = $!{obj}</p>

#foreach( $item in $!{objlist} )
  #set($obj[$item.k] = $item)
#end
<p>结果值 obj = $!{obj}</p>
<p>输出 {undefined={k=c}}，在java端解析返回的是包含 a,b,c 3个key的对象</p>
<h1>循环给数组赋值(index)</h1>
#set($ary = [])
<p>初始值 ary = $!{ary}</p>

#foreach( $item in $!{objlist} )
  #set($index = $velocityCount - 1)
  #set($obj[$index] = $item)
#end
<p>结果值 ary = $!{ary}</p>
<p>输出 []</p>
