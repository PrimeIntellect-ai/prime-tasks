Memory experiments are not valid as block graph
## Describe the bug
I'm not sure if this is the intended behavior but we cannot generate a simple memory experiment as `ZXGraph` and convert it to a `BlockGraph`.

## Steps to reproduce the behavior:
```python
cubes = [
    (Position3D(0, 0, 0), CubeType.ZXZ),
    (Position3D(0, 0, 1), CubeType.ZXZ),
]
pipes = [
    (cubes[0][0], cubes[1][0], PipeType.ZXO),
]
block_graph = BlockGraph(name="Memory Experiment")
for cube in cubes:
    block_graph.add_cube(*cube)
block_graph.add_pipe(*pipes[0])
zx_from_block_graph = block_graph.to_zx_graph()
new_block_graph = BlockGraph.from_zx_graph(zx_from_block_graph) #<--This fails
```

## Expected behavior
I would expect this to work. Unfortunately, [from_zx_graph](https://github.com/QCHackers/tqec/blob/3ce9649c528fc245ecdb85a5c8a52e94806f88b9/src/tqec/sketchup/block_graph.py#L496) is locking for a corner block.

## Screenshots and MP4s
![Figure_1](https://github.com/user-attachments/assets/d075b977-add7-4f3e-a166-b4708c9619e5)

### Additional contract requirements

- Additionally, `ZXGraph.to_block_graph()` must produce cubes of type `CubeType.XZZ` at both positions `Position3D(0, 0, 0)` and `Position3D(0, 0, 1)` when Z nodes at those positions are joined by an ordinary edge. For a Z node at `Position3D(0, 0, 0)` and an X node at `Position3D(1, 0, 0)` joined by an edge with `has_hadamard=True`, it must produce cubes of type `CubeType.ZXZ` and `CubeType.XZX` at those positions, respectively.
