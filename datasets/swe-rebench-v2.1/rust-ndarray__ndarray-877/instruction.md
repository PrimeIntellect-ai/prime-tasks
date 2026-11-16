and_broadcast_mut for Zip
Currently Zip has no mutable equivalent for the `and_broadcast` method, which is presumably to allow it to safely be `split()` and parallelized. However this makes some calculations difficult. The examples below are for backprop through a broadcast-able element-wise multiplication, but the problem appears as a pattern often.

Currently I'm looking at using this:
```
unsafe{
	let input2_grad = data.get_mut(&self.input2_id.gradient_id())?;

	// do not split/parallelise this Zip!
	Zip::from(&input1)
		.and(&output_grad)
		.and_broadcast(&input2_grad)
		.apply(|input1, out_grad, input2_grad| {
			let input2_grad = input2_grad as *const f32 as *mut f32;
			*input2_grad += input1 * out_grad;
		});
}
```
which works correctly, but also has UB written all over it depending on how Zip is implemented internally (I realize Zip owes me nothing here).

The safe alternative I've found is:
```
let iter = input1.exact_chunks(input2.shape()).into_iter()
	.zip(output_grad.exact_chunks(input2.shape()));

for (input1_chunk, out_grad_chunk) in iter {
	Zip::from(&mut input2_grad)
		.and(&input1_chunk)
		.and(&out_grad_chunk)
		.apply(|input2_grad, input1, out_grad| {
			*input2_grad += input1 * out_grad;
		});
}
```
which is catastrophically (over 30x) slower for some cases.

So my questions are:
 * is there a safe high performance workaround that I've missed?
 * would it be possible to add a `and_broadcast_mut()` method which would set a flag or something which makes `split()` panic?

### Additional contract requirements

- Add a public method `cell_view` on `ArrayBase` with the signature `fn cell_view(&mut self) -> ArrayView<'_, MathCell<A>, D>`, available for arrays whose storage implements `DataMut`. It returns a shared view whose elements are `MathCell<A>`. The returned view can be copied and traversed more than once (for example, two copies of the same view can be used together in a `Zip`), and elements can be read and modified through the cell API (`get`, `set`, ...).
- Add a public type `MathCell<T>` exported at the crate root as `ndarray::MathCell`. It is a transparent wrapper around `std::cell::Cell<T>` with the same memory layout, and it dereferences to `Cell<T>` so that all `Cell` methods (`get`, `set`, ...) are available on it.
