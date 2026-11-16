header and footer string not escaped
In XML, the & character should be escaped.


| Original character | Escaped character  |
|--------------------| ------------------ |
|          "         |        &amp;quot;      |
|          '         |        &amp;apos;      |
|          <         |        &amp;lt;        |
|          >         |        &amp;gt;        |
|          &         |        &amp;amp;       |


https://www.w3.org/TR/REC-xml/#syntax (2.4 Character Data and Markup)


``` Java
  ws.header("<Left> & 'left' & \"LEFT\"", Position.LEFT, "Calibri", 12)
  ws.header("<Center> & 'center' & \"CENTER\"", Position.CENTER, "Calibri", 12)
  ws.header("<Right> & 'right' & \"RIGHT\"", Position.RIGHT, "Calibri", 12)
```

The output sheet1.xml is not escaped and cannot be opened in Excel.

sheet1.xml
```xml
  <headerFooter differentFirst="false" differentOddEven="false">
        <oddHeader>&amp;L&amp;&quot;Calibri,Regular&quot;&amp;12&amp;K000000<Left> & 'left' & "LEFT"&amp;C&amp;&quot;Calibri,Regular&quot;&amp;12&amp;K000000<Center> & 'center' & "CENTER"&amp;R&amp;&quot;Calibri,Regular&quot;&amp;12&amp;K000000<Right> & 'right' & "RIGHT"</oddHeader>
        <oddFooter></oddFooter>
  </headerFooter>

```
