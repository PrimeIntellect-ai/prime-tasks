Sometimes when rebuilding tree, and then selecting text, the following assertion is received.
<!-- Thank you for using Fleather! -->

## Steps to Reproduce

<!-- Please tell us exactly how to reproduce the problem you are running into. -->

1. Rebuild tree in some form, then select text.
2. Assertion received

## Environment
- Mac OS 12.6
- Flutter version 3.16.4
- Fleather version 1.14.1

## Logs

```
======== Exception caught by widgets library =======================================================
The following assertion was thrown building _RenderTheaterMarker:
A ValueNotifier<bool> was used after being disposed.

Once you have called dispose() on a ValueNotifier<bool>, it can no longer be used.
The relevant error-causing widget was:
  MaterialApp MaterialApp:file:///Users/nialljawad/StudioProjects/purple/lib/main.dart:148:14
When the exception was thrown, this was the stack:
#0      ChangeNotifier.debugAssertNotDisposed.<anonymous closure> (package:flutter/src/foundation/change_notifier.dart:179:9)
#1      ChangeNotifier.debugAssertNotDisposed (package:flutter/src/foundation/change_notifier.dart:186:6)
#2      ChangeNotifier.addListener (package:flutter/src/foundation/change_notifier.dart:271:27)
#3      _SelectionHandleOverlayState.initState (package:fleather/src/widgets/text_selection.dart:1399:24)
#4      StatefulElement._firstBuild (package:flutter/src/widgets/framework.dart:5602:55)
#5      ComponentElement.mount (package:flutter/src/widgets/framework.dart:5447:5)
...     Normal element mounting (35 frames)
#40     Element.inflateWidget (package:flutter/src/widgets/framework.dart:4326:16)
#41     MultiChildRenderObjectElement.inflateWidget (package:flutter/src/widgets/framework.dart:6871:36)
#42     Element.updateChild (package:flutter/src/widgets/framework.dart:3837:18)
#43     Element.updateChildren (package:flutter/src/widgets/framework.dart:4024:32)
#44     MultiChildRenderObjectElement.update (package:flutter/src/widgets/framework.dart:6896:17)
#45     Element.updateChild (package:flutter/src/widgets/framework.dart:3815:15)
#46     ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5496:16)
#47     StatefulElement.performRebuild (package:flutter/src/widgets/framework.dart:5634:11)
#48     Element.rebuild (package:flutter/src/widgets/framework.dart:5187:7)
#49     BuildOwner.buildScope (package:flutter/src/widgets/framework.dart:2895:19)
#50     WidgetsBinding.drawFrame (package:flutter/src/widgets/binding.dart:984:21)
#51     RendererBinding._handlePersistentFrameCallback (package:flutter/src/rendering/binding.dart:457:5)
#52     SchedulerBinding._invokeFrameCallback (package:flutter/src/scheduler/binding.dart:1325:15)
#53     SchedulerBinding.handleDrawFrame (package:flutter/src/scheduler/binding.dart:1255:9)
#54     SchedulerBinding._handleDrawFrame (package:flutter/src/scheduler/binding.dart:1113:5)
#55     _invoke (dart:ui/hooks.dart:312:13)
#56     PlatformDispatcher._drawFrame (dart:ui/platform_dispatcher.dart:383:5)
#57     _drawFrame (dart:ui/hooks.dart:283:31)
====================================================================================================

```

Appears to be related to this in the text_selection.dart:

```
  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
        duration: SelectionOverlay.fadeDuration, vsync: this);

    _handleVisibilityChanged();
    widget.visibility?.addListener(_handleVisibilityChanged);
  }

  void _handleVisibilityChanged() {
    if (widget.visibility?.value ?? true) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }
```

Is there a way to get around this/mitigate against it?
