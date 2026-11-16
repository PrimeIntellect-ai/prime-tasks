Pause and resume (In a quick succession) gets you  lot of exceptions and an infinite loop
Doing pause and resume (In a quick succession) on demo gets you  lot of exceptions :-

```
papaparse.js:733 Uncaught DOMException: Failed to execute 'readAsText' on 'FileReader': The object is already busy reading Blobs.
    at FileStreamer._readChunk (https://www.papaparse.com/resources/js/papaparse.js:733:21)
    at FileStreamer._nextChunk (https://www.papaparse.com/resources/js/papaparse.js:722:10)
    at FileStreamer.ChunkStreamer.parseChunk (https://www.papaparse.com/resources/js/papaparse.js:538:10)
    at FileStreamer._chunkLoaded (https://www.papaparse.com/resources/js/papaparse.js:743:9)
    at FileReader.<anonymous> (https://www.papaparse.com/resources/js/papaparse.js:1800:25)
FileStreamer._readChunk	@	papaparse.js:733
FileStreamer._nextChunk	@	papaparse.js:722
ChunkStreamer.parseChunk	@	papaparse.js:538
FileStreamer._chunkLoaded	@	papaparse.js:743
(anonymous)	@	papaparse.js:1800
load (async)
FileStreamer.stream	@	papaparse.js:710
CsvToJson	@	papaparse.js:265
parseNextFile	@	papaparse.js:163
$.fn.parse	@	papaparse.js:113
(anonymous)	@	demo.js:103
dispatch	@	jquery.min.js:3
r.handle	@	jquery.min.js:3
```
And if you choose to handle them, like this :-
```
function stepFn(results, parser)
{
	stepped++;
	if (results)
	{
		parser.pause();
		try{
		parser.resume();
		} catch (e) {
			console.log(e);
		}
		if (results.data){
			array2 = array2.concat(results.data); // Just to check the data
			rowCount += results.data.length;
		}
		if (results.errors)
		{
			errorCount += results.errors.length;
			firstError = firstError || results.errors[0];
		}
	}
}
```
Then you get into an infinite loop with the same data.

It appears that resume should be waiting for previous pause to halt the parsing before continuing again.
It appears this wasn't the case before since Issue #321 talks about doing this to produce another bug (Cursor related).
I am using :-
`Papa.LocalChunkSize = 10485`
Otherwise you get :-
```
RangeError: Maximum call stack size exceeded
    at FileStreamer.ChunkStreamer.parseChunk (papaparse.js:491)
    at ParserHandle.resume (papaparse.js:1078)
    at stepFn (demo.js:212)
    at ParserHandle._config.step (papaparse.js:1017)
    at doStep (papaparse.js:1651)
    at Parser.parse (papaparse.js:1561)
    at ParserHandle.parse (papaparse.js:1058)
    at FileStreamer.ChunkStreamer.parseChunk (papaparse.js:489)
    at ParserHandle.resume (papaparse.js:1078)
    at stepFn (demo.js:212)
```

### Additional contract requirements

- The parser object passed to the `step` callback exposes `pause()` and `resume()` methods.
- Calling `resume()` immediately after `pause()` (in quick succession) must not throw and must not re-deliver data that was already parsed; parsing continues only after the previous pause has halted.
