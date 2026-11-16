Configure the depth limit for item indentation
After a particular depth, don't insert newlines any more, e.g. (from @pyfisch custom format):
```
┌ Display List
│  ├─ ClipScrollNodes
│  │  └─ ClipScrollNode { id: Some(Clip(0, PipelineId(0, 1))), parent_index: ClipScrollNodeIndex(0), clip: ClippingRegion::Empty, content_rect: TypedRect(0.0×0.0 at (0.0,0.0)), node_type: ScrollFrame(ScriptAndInputEvents) }
│  ├─ Items
│  │  ├─ PushStackingContext(StackingContext at TypedRect(1024px×1077.2333333333333px at (0px,0px)) with overflow TypedRect(1024px×1077.2333333333333px at (0px,0px)): StackingContextId(0)) StackingContext: StackingContextId(0) ClippingAndScrolling { scrolling: ClipScrollNodeIndex(0), clipping: None }
│  │  ├─ SolidColor rgba(0, 0, 0, 0) @ TypedRect(1024px×1077.2333333333333px at (0px,0px)) Rect(TypedRect(1024.0×1077.2333 at (0.0,0.0))) StackingContext: StackingContextId(0) ClippingAndScrolling { scrolling: ClipScrollNodeIndex(0), clipping: None }
```

### Additional contract requirements

- `ron::ser::PrettyConfig` has a public field `depth_limit: usize`.
- `depth_limit` bounds the nesting depth at which pretty formatting is applied. The elements of the top-level value are at nesting depth 1, and each further level of nesting increases the depth by one. Line breaks and indentation are inserted for a container's elements only while those elements are at a nesting depth strictly less than `depth_limit`; at nesting depth `depth_limit` and deeper, elements are written on the same line with no indentation.
- `ron::ser::PrettyConfig` has public fields `separate_tuple_members: bool` and `enumerate_arrays: bool`. When `separate_tuple_members` is true, tuple elements within the depth limit are placed on separate lines. When `enumerate_arrays` is true, array elements within the depth limit are annotated with their index.
- `ron::ser::to_string_pretty(value: &T, config: PrettyConfig) -> Result<String, ron::error::Error>` serializes `value` using `config`.
