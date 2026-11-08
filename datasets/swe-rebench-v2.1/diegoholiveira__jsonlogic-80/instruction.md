Apply issue in go client
rule = {"and":[{"in":[{"var":"flow"},["BRAND"]]},{"or":[{"if":[{"missing":["gender"]},true,false]},{"some":[{"var":"gender"},{"==":[{"var":null},"men"]}]}]}]}

data= {"category":["sneakers"],"flow":"BRAND","gender":["men"],"market":"US"}


err = jsonlogic.Apply(bytes.NewReader(rule), bytes.NewReader(data), &resultBuffer)

getting error in this case
 interface conversion: interface {} is map[string]interface {}, not string

 but this case pass in playground/ javascript client
