# Ranking: how the panel decides what comes first

Written 2026-10-19. Code: `Sources/Apropos/Search` (matcher, ranker, tuning, simulation), `Sources/Apropos/Usage`
(what is learned), `Sources/Apropos/Prediction` (what usually comes next).

## What the old ranking did, and where it was weak
1. **Typing:** a fuzzy score (letters in order, bonuses for word starts and runs) plus a capped boost from use. Nothing knew
   that typing the *start* of a name is a stronger signal than letters that happen to be in it, so "rec" could rank
   "Add to Reading List" next to "Open Recent".
2. **Use:** frecency, a count times the average of five step weights. It ignored time between runs beyond five buckets and was
   added to every match equally, so a heavily used command could lift a poor match.
3. **No slips:** "shwo" found nothing. Accents mattered: "resume" did not find "Résumé".
4. **No context:** typing ignored what you had just run, even though Usually next already knew. Browsing (no typing) listed the
   menus in menu order with five suggestions on top.
5. **No learning of your own names:** nothing connected what you type to what you pick.

## What it does now
| Part | Behaviour |
|---|---|
| Match kind | The matcher says whether the query is an exact title, its start, the start of a word, the first letters of words, or scattered. Each kind has its own bonus. A long title loses a little against a short one the query fully covers (typing "clo" means Close before Close Other Tabs). |
| Slips | If nothing matched cleanly, one swap of two neighbouring letters is tried. Accents and case are ignored. |
| Use | Each remembered run counts for half as much every 21 days. The boost is smooth and capped, and is scaled by how good the text match is, so use lifts a good match and never rescues a poor one. |
| What comes next | The prediction model's chance that a command is next (after the last command, at this time, in this context) adds up to 45 points to a match, scaled the same way. |
| Your names | When you run a command after typing an abbreviation of its name, that is remembered (letters only, up to 16 characters, at most 8 per command). When a name has led to the same command at least 3 times and in at least 60% of the cases, typing it ranks that command first, and finds it even if the name is not in its title. |
| Browsing | Inside each menu, the commands you use come first; menus keep their order. |

Privacy: a remembered name is only stored when it is an abbreviation of the command's own title, path or keywords, so it is a
fragment of a command name, never free text. It is in `usage.json`, shown under Privacy and data as part of "Usage and
ranking", and Forget clears it.

## How it was measured
`RankingSimulation` builds five apps with realistic menus and simulated people: favourites that follow a Zipf curve, short
routines (after A comes B), a share of random exploration, habits that drift, and six ways of reaching a command (browse,
type the start, type the first letters, type a word from the middle, a personal shorthand, a typo). `RankingEvaluation`
runs a person through 800 to 1200 runs, learning as it goes, and scores the second half. **Cost** is keystrokes plus half a
point per arrow press until the right command is chosen; lower is better.

Averages over four to eight simulated people:

| | cost | first at stop | in top 3 | typo habit | browse |
|---|---|---|---|---|---|
| old ranking | 2.45 | 60.9% | 89.8% | 1.92 | 6.87 |
| now | 2.11 | 70.7% | 91.1% | 1.65 | 5.80 |

That is about 14% fewer keystrokes-and-arrows, and ten points more often exactly first. With habits that drift part way,
the gap holds (2.01 against 2.37). Without the what-comes-next prior the cost is 2.20, so the prior accounts for a third of
the gain. Typo tolerance is the only change that fixed a case that used to find nothing at all.

**What did not matter:** the individual weights. Halving or doubling the usage cap, the prefix bonus, the length penalty,
the initials bonus and the half-life moved the cost by less than 0.03, so the defaults are not fragile. Learned names help a
little in a world without routines and are neutral with them, so they are gated strictly rather than turned up.

**What this cannot tell you:** the simulation shows the code finds structure that is in the data; it cannot show that your
Mac has that structure. The honest test is a few weeks of use. Run `APROPOS_RANK_EVAL=1 swift test --filter
RankingEvaluationTests` to repeat the comparison or try a setting (it takes a few minutes in a debug build, which is why it
is off by default).

## Not done yet
- Learning from what you ignore (a command shown first and skipped).
- Ranking by what is selected beyond the small bonus for context actions, and by time of day outside the prediction model.
- Synonyms ("mail" for Compose) are not learned on purpose: storing them would mean storing words that are not part of any
  command name.
