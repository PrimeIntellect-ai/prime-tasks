Progress bar: length must be 2 or greater, was 1
See https://github.com/russellbanks/Komac/issues/102:

GitHub runners sometimes produce this error with progress bars:

```
   Exception in thread "Timer-0" java.lang.IllegalArgumentException: length must be 2 or greater, was 1
  	at com.github.ajalt.colormath.transform.InterpolateKt.sequence(Interpolate.kt:158)
  	at com.github.ajalt.mordant.widgets.ProgressBar.makeComplete(ProgressBar.kt:107)
  	at com.github.ajalt.mordant.widgets.ProgressBar.render(ProgressBar.kt:86)
  	at com.github.ajalt.mordant.widgets.Padded.render(Padding.kt:99)
  	at com.github.ajalt.mordant.table.TableRenderer.<init>(Table.kt:246)
  	at com.github.ajalt.mordant.table.TableImpl.render(Table.kt:121)
  	at com.github.ajalt.mordant.rendering.Widget$DefaultImpls.render$default(Widget.kt:7)
  	at com.github.ajalt.mordant.animation.Animation.update(Animation.kt:76)
  	at com.github.ajalt.mordant.animation.ProgressAnimation.tick(ProgressAnimation.kt:164)
  	at com.github.ajalt.mordant.animation.ProgressAnimation.access$tick(ProgressAnimation.kt:91)
  	at com.github.ajalt.mordant.animation.ProgressAnimation$start$1.invoke(ProgressAnimation.kt:154)
  	at com.github.ajalt.mordant.animation.ProgressAnimation$start$1.invoke(ProgressAnimation.kt:153)
  	at com.github.ajalt.mordant.animation.JvmTicker$start$$inlined$timer$default$1.run(Timer.kt:149)
  	at java.base/java.util.TimerThread.mainLoop(Timer.java:566)
  	at java.base/java.util.TimerThread.run(Timer.java:516)
```

```kotlin
fun getDownloadProgressBar(url: Url, terminal: Terminal): ProgressAnimation {
    return terminal.progressAnimation {
        url.getFileName()?.let { text(it) }
        percentage()
        progressBar()
        completed()
        speed("B/s")
        timeRemaining()
    }
}
```

```kotlin
getDownloadProgressBar(url, this).run {
    start()
    prepareGet(url).execute { httpResponse ->
        val channel: ByteReadChannel = httpResponse.body()
        while (!channel.isClosedForRead) {
            val packet = channel.readRemaining(DEFAULT_BUFFER_SIZE.toLong())
            while (packet.isNotEmpty) {
                file.appendBytes(packet.readBytes())
                update(file.length(), httpResponse.contentLength())
            }
        }
    }
    clear()
}
```
