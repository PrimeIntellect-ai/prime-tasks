Run Fixing Algorithms when opening splits

### Additional contract requirements

- When a run is opened through `Editor::new` or `Timer::new`, repair its split histories before exposing it for editing or timing.
- After construction, segment-history data must remain available and consistent; entries that lack corresponding attempt-history records must be repaired rather than discarded or left orphaned.
