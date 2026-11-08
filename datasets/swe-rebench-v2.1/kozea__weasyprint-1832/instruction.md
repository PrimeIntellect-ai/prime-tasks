Half of word-spacing to a space at the end of a TextBox
Hello, I get different results from Chrome and Weasyprint when trying to use word-spacing in text that ends with a space.  Weasyprint only adds half of word-spacing to these cases.

The following code illustrates the problem.

```html
<style type="text/css">
	@page { size: 200px; margin: 0 }
	body { margin: 0; font: 15pt monospace }
	.ws { word-spacing: 50px }
	.ws2 { word-spacing: 100px }
</style>
<div class="ws">a b</div>
<div class="ws">c <b></b>d</div>
<div class="ws2">e <b></b>f</div>
```

WeasyPrint:
![image](https://user-images.githubusercontent.com/70984536/222994077-57ef0cff-df03-4a6e-b10c-10c5998ce7cc.png)

Chrome:
![image](https://user-images.githubusercontent.com/70984536/222994042-83bc5c23-6304-4f95-86ed-3be188eeb69d.png)

I found a reference to this problem in this TODO:
https://github.com/Kozea/WeasyPrint/blob/4377c38b2971a3a3c6c7f3a6de2c49a585d65f68/tests/test_text.py#L473-L474

Currently, I am fixing this problem changing this code
https://github.com/Kozea/WeasyPrint/blob/4377c38b2971a3a3c6c7f3a6de2c49a585d65f68/weasyprint/text/line_break.py#L184-L190

to this
[HIDDEN]

### Additional contract requirements

- When word-spacing applies, a space that ends a run of text (including a space that is the only content of an inline element) must receive the full word-spacing amount, not only half.
