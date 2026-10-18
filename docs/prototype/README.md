# Design prototype

Throwaway HTML prototype of the Apropos panel: glass look, context chips, app switching, fuzzy search, actions menu
and the record-to-command flow. Not product code. It exists to judge look and motion before building them natively.

Run it:

```bash
cd docs/prototype && python3 -m http.server 5731
```

Then open http://127.0.0.1:5731. Switch app in the dock, press Cmd+K for actions, Cmd+R to record, L for light or
dark, Option+Space to toggle the panel.

Design decisions it encodes: no open or close animation (used hundreds of times a day), motion only where it
explains a change (selection highlight, context change, recording steps), one mint accent used sparingly.

## v2: density and icon comparison

`v2.html` compares the previous, current and proposed layouts at 1:1 scale with three row-icon options. Decision: the Proposed layout with Glyph icons (a tile on every row). Serve it the same way and open http://127.0.0.1:5731/v2.html at 100% zoom.
