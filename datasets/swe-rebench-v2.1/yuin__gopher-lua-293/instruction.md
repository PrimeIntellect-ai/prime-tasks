os.time failed when it be called with a table which fields has string value
1. What version of GopherLua are you using? : `master branch`
2. What version of Go are you using? : `go1.14.2`
3. What operating system and processor architecture are you using? : `darwin/amd64`
4. What did you do? : `calling os.time() with a table which field is string. eg: t1 = {year = "2006", month = "01", day = "02", hour = "15",  min = "04", sec = "05"}`
5. What did you expect to see? : `os.time(t1) return value equal 1136185445`
6. What did you see instead? : `os.time(t1) return value is -62204184343`

Standard lua interpreter support calling `os.time ([table])` with a table which field is string. And I understand it only support convert decimal and hexadecimal to number([lua convert string to number code](https://github.com/lua/lua/blob/v5.1.1/lobject.c#L90)). When string has prefix '0' and ' ', it just trim it all. I think we should keep consistent with standard implementation in the right situation.

I have test standard implementation as shown in the figure below:
![image](https://user-images.githubusercontent.com/10355814/86525750-d6333d00-bebd-11ea-8674-d3f7b6f29c8f.png)
