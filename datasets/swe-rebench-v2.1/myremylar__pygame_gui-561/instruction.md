Changing object class and rebuild does not update object to new theme
**Describe the bug**
The following changes the theme class id of the object, but the visual display in the window display in the window does not update to reflect the new theme.

```
new_task_desc = pygame_gui.elements.UITextEntryBox(
    relative_rect=pygame.Rect((25, 92), (635, 32)),
    initial_text="",
    object_id=ObjectID(class_id="@add_ok"),
    manager=manager,
)

# Some event occurs and there is an error to be highlighted.

new_task_desc.class_ids = ["@add_error"]
# Rebuild the element to reflect the new class.
new_task_desc.rebuild()
```

Have checked that it is not being overidden by object level theme. Defaults removed from theme file and no other container that could be overriding theme class id identified.

**To Reproduce**
See example files attached.

[pygame_gui_class_bug.zip](https://github.com/MyreMylar/pygame_gui/files/11710375/pygame_gui_class_bug.zip)

**Expected behaviour**
When the class_id of a object changes, display should update to reflect new theme. Preferably without having to call a rebuild.

**Screenshots**
N/A - see sample files.

**Platform and software (please complete the following information):**
 - OS: Windows 10
 - Pygame GUI version 0.6.9
 - Pygame version 2.4.0

**Additional context**
It is quite possible that this is user-error and I haven't understood something. I have spent nearly three hours trying to solve this problem and have run out of ideas. Any assistance appreciated.
