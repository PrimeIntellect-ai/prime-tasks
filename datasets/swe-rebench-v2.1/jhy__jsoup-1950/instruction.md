Attributes in form-elements are not deduplicated when parsing as HTML
I have an issue with form-elements that contains duplicate attributes. I was expecting that attributes in form-elements should be deduplicated in the same way as all other elements when parsing HTML via Parser.htmlParser() but duplicate attributes seems to always be retained. Using Parser.xmlParser(), form attributes are correctly deduplicated so the issue only affects HTML.

Looking though old issues and pull requests, I found #1219 that seems to fix deduplication for start tags but that fix doesn't seems to apply to form-elements.

Here is a simple test-case adopted from `HtmlParserTest`:

```
    @Test public void dropsDuplicateAttributesInFormElement() {
        String html = "<form One=One ONE=Two Two=two one=Three One=Four two=Five></form>";
        Parser parser = Parser.htmlParser().setTrackErrors(10);
        Document doc = parser.parseInput(html, "");

        Element p = doc.selectFirst("form");
        assertEquals("<form one=\"One\" two=\"two\"></form>", p.outerHtml()); // normalized names due to lower casing

        assertEquals(1, parser.getErrors().size());
        assertEquals("Dropped duplicate attribute(s) in tag [form]", parser.getErrors().get(0).getErrorMessage());
    }
```
