IDs and Styles leak from internal elements when Mustache Style Injectors are used
### Your idea:

When using an inline or block style injector, attributes like style or ID from internal elements leak to their parents.

Reproduction:
```
{{test
# H1
}}
{}
```

Even though there is nothing to inject into the wrapping block, we receive the following HTML output:
```
<div class="block test" id="h1">
<h1 id="h1">h1</h1>
</div>
```

This is most noticeable when using the image masks; some users have been adding styling like so:
```
{{imageMaskEdge2,--offset:0%,--rotation:180
  ![](https://i.imgur.com/GZfjDWV.png){height:100%}
  {--test:true}
}}
```

which is resulting in:
```
<div class="block imageMaskEdge2" style="--offset:0%; --rotation:180;">
<p style="height:100%; --test:true;" src="https://i.imgur.com/GZfjDWV.png" alt="">
  <img style="height:100%;" src="https://i.imgur.com/GZfjDWV.png" alt="">
</p>
</div>
```

The `--test:true` is correctly applied to the `<p>`, but the `<height:100%>` has been incorrectly applied from the internal `<img>` styling.
