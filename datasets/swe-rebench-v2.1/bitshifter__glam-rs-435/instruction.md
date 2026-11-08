lerp over scalar types?
Hello!

I'm using glam via bevy. Ran into a situation where I need to lerp over a single f32 value i.e. non-vector. I couldn't find a function for it in glam, so I would either need use Vec2::lerp and de-structure the single value out of it, or write my own boilerplate code.

Is this even in the scope of this project? Or should this be implemented as utils in bevy?

### Additional contract requirements

Add scalar linear interpolation for `f32` to glam. Make it available through the public `FloatExt` trait as `f32::lerp(start, end, t)` when the trait is in scope. The result is the value a fraction `t` of the way from `start` to `end`; in particular, `t = 0` returns `start` and `t = 1` returns `end`.
