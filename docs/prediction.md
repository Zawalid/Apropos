# Next-action prediction

Apropos learns which command the person usually runs next and offers it under **Usually next**, with one key and an
honest reason. Everything is local: counting tables built from a small run log, no network, no model file, nothing
that cannot be explained in a sentence.

## The run log

`~/Library/Application Support/Apropos/sequence.json`, separate from `usage.json`. Owner-only permissions (0600),
written atomically (temporary file then rename) at most every five seconds and on quit, off the main thread.

```json
{"schemaVersion":1,"events":[
  {"t":1800000000,"c":"com.apple.dt.xcode|product>test","a":"com.apple.dt.Xcode","x":["branch","document"]},
  {"t":1800000042,"c":"com.apple.terminal|shell>new tab","a":"com.apple.Terminal","p":"com.apple.dt.xcode|product>test","o":"com.apple.terminal|shell>new tab"}
]}
```

### Exactly what is stored, per event

| Key | Field | Content |
| --- | --- | --- |
| `t` | time | whole seconds since 1970 |
| `c` | command | the stable `CommandID` (bundle id, menu path, title; or a context action id such as `ctx:text.upper`) |
| `a` | app | bundle identifier of the frontmost app, only when it looks like one, else omitted (`unknown`) |
| `p` | previous | the `CommandID` that ran just before, if it was less than 10 minutes earlier |
| `x` | contextKinds | which kinds of context were present, from the fixed set `document url folder branch selection selectionCount`. Kinds only |
| `o` | offered | the `CommandID` that was shown under Usually next when the palette opened, if any |
| `k` | kind | only written for `dismiss` (the person chose Not now on a prediction); a plain run omits it |

### What is never stored

Selection text, URLs, document or file names or paths, search queries, window titles, tab titles, clipboard
contents. There is no field that could hold them: the event type has exactly the seven fields above, the initializer
sanitises each (the app must look like a bundle identifier, the kinds must be one of the six names, the command
identity must pass `PredictionPrivacy.isLoggable`), and a line in the file that would not be written today is dropped
when read. Tests assert all of this.

One residual risk is in the command identity itself: a menu item title is part of the identity, and a few menus are made
of the person's content (the Window menu lists document names, History and Bookmarks list pages, Open Recent lists
files). Commands under those menus, in English, French, German, Spanish, Italian and Portuguese, are not logged at all
(`PredictionPrivacy.contentMenus`). This is a best-effort list; a localisation it does not know would be logged as a
menu command. Identities over 200 characters or with a line break are refused.

### Lifetime

- Rotated by age (400 days) and by count (40 000 events; the oldest are dropped, in steps of 2 000 so it is not done on
  every run).
- A damaged file is copied to `sequence.json.broken-<timestamp>` and the log starts empty. A single bad line is skipped
  and the rest kept. A file from a newer schema version is read but never overwritten.
- **Reset learned ranking** clears it. It is not part of any export.
