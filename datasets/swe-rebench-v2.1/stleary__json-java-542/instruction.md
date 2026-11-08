Issue while converting xml to json
xml: <tag>Hypersegmented &#X7C; Bld-Ser-Pla</tag>

Caller method:
JSONObject xmlJSONObj = XML.toJSONObject(xml, true);

Error:
Caused by: java.lang.NumberFormatException: For input string: "X7C"
	at java.lang.NumberFormatException.forInputString(NumberFormatException.java:65) ~[na:1.8.0_201]
	at java.lang.Integer.parseInt(Integer.java:580) ~[na:1.8.0_201]
	at java.lang.Integer.parseInt(Integer.java:615) ~[na:1.8.0_201]
	at org.json.XML.unescape(XML.java:200) ~[json-20170516.jar:na]
	at org.json.XML.parse(XML.java:398) ~[json-20170516.jar:na]
	at org.json.XML.parse(XML.java:403) ~[json-20170516.jar:na]
	at org.json.XML.toJSONObject(XML.java:485) ~[json-20170516.jar:na]

Error at calle:
at org.json.XML.  public static String unescape(String string)

Error prone code piece
 [HIDDEN]

### Additional contract requirements

- XML text containing an uppercase-X hexadecimal numeric character reference, such as `&#X7C;`, must decode to its corresponding character (for example, `|`) rather than causing an exception.
