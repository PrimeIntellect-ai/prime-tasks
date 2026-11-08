v63.0 flexbox issue overflow hidden
With v63.0 the following code breaks:

```
<html>
<head>
<style>
    .wrapper {
      display: flex;
    }
    .cell {
      flex: 1;
      border: 1px solid black;
      padding: 10px;
      overflow: hidden;
    }
  </style>
</head>
<body>
  <div class="wrapper">
    <div class="cell">one</div>
    <div class="cell">two</div>
    <div class="cell">three</div>
    <div class="cell">four</div>
    <div class="cell">five</div>
    <div class="cell">six</div>
    <div class="cell">seven</div>
    <div class="cell">eight</div>
    <div class="cell">nine</div>
  </div>
</body>
</html>
```

When overflow: hidden is added to .cell, all cells appear on top of each other instead of next to each other.
