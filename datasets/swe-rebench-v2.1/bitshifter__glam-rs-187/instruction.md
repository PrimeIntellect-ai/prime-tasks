".fract" for vector types
(Minor convenience thing, absolutely not urgent in any way).

In GLSL, fract is quite commonly used, in things like this hash function in https://www.shadertoy.com/view/tlGfzd:

```glsl
// by Dave_Hoskins
float hash12(vec2 p)
{
    vec3 p3  = fract(vec3(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}
```

It just returns the fractional value, or `x - floor(x)`:  (https://www.khronos.org/registry/OpenGL-Refpages/gl4/html/fract.xhtml).

Having this in glam would be convenient when translating GLSL shaders to rust-gpu, for example.
