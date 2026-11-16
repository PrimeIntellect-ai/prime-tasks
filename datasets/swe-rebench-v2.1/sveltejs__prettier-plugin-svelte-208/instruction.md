Comments get removed from formated Svelte Component
Hi when I format a svelte component, any comment that is at the end of an element gets removed.

Gets removed:
```
<div>
    <div/>
    <!-- testing 123 -->
</div>
```

Doesn't get removed:
```
<div>
    <!-- testing 123 -->
    <div/>
</div>
```

Any solutions?
