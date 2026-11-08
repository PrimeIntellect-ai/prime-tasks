Fails to detect inside of HTML tag
If the inner text of an HTML tag can be found in the tag attributes itself, then we fail to parse it properly:

```html
<a href="mylink">mylink</a>
```

yields:

```jsx
      -          {
      -            "data": {
      -              "html": "<a href=\""
      -            }
      -            "isVoid": true
      -            "kind": "inline"
      -            "nodes": [
      -              {
      -                "kind": "text"
      -                "ranges": [
      -                  {
      -                    "kind": "range"
      -                    "marks": []
      -                    "text": " "
      -                  }
      -                ]
      -              }
      -            ]
      -            "type": "html"
      -          }
      -          {
      -            "kind": "text"
      -            "ranges": [
      -              {
      -                "kind": "range"
      -                "marks": []
      -                "text": "mylink"
      -              }
      -            ]
      -          }
```
