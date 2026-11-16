5.0.0-beta.0 header: true, worker: false, steps... incorrectly parses headers
Here is a failing test:
```
AssertionError: expected '[[{"O":"A"},{"O":"b"},{"O":"c"}],[{"O":"d"},{"O":"E"},{"O":"f"}]]' to deeply equal '[{"One":"A","Two":"b","Three":"c"},{"One":"d","Two":"E","Three":"f"}]'
      + expected - actual

      -[[{"O":"A"},{"O":"b"},{"O":"c"}],[{"O":"d"},{"O":"E"},{"O":"f"}]]
      +[{"One":"A","Two":"b","Three":"c"},{"One":"d","Two":"E","Three":"f"}]
```
<details>
<summary>code</summary>

```js
	{
		description: "Data is correctly parsed with steps (headers)",
		expected: [{One: 'A', Two: 'b', Three: 'c'}, {One: 'd', Two: 'E', Three: 'f'}],
		run: function(callback) {
			var data = [];
			Papa.parse('One,Two,Three\nA,b,c\nd,E,f', {
				header: true,
				step: function(results) {
					data.push(results.data);
				},
				complete: function() {
					callback(data);
				}
			});
		}
	},
	{
		// The worker code path does work,
		// This fails because node doesn't expose Workers yet ... so this falls back to the non-worker path.
		// See: https://nodejs.org/api/worker_threads.html
		description: "Data is correctly parsed with steps and worker (headers)",
		expected: [{One: 'A', Two: 'b', Three: 'c'}, {One: 'd', Two: 'E', Three: 'f'}],
		run: function(callback) {
			var data = [];
			Papa.parse('One,Two,Three\nA,b,c\nd,E,f', {
				header: true,
				worker: true,
				step: function(results) {
					data.push(results.data);
				},
				complete: function() {
					callback(data);
				}
			});
		}
	},
```

</details>
