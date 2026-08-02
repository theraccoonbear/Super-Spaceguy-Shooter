# Speech synthesizer (`src/audio/speech.bas`)

## What problem it solves

The game narrates its crawl text and in-flight callouts out loud, with zero audio assets and zero external TTS dependency. Everything is synthesized sample-by-sample at runtime from phoneme data, the same way `music.bas` and `snd.bas` synthesize music and sound effects instead of playing files.

## Pipeline overview

```
assets/gametext.txt + gamevalues.ini   (source text, with {{token}} substitution)
              │
              ▼  tools/bake_speech_dict  (build-time, not runtime)
assets/speech_dict.txt                 (word → ARPAbet phoneme entries actually used)
              │
              ▼  $EMBED + SPK_LoadDict  (startup)
in-memory dictionary (binary search)
              │
              ▼  SPK_Say(text$)          (runtime, called with in-game text)
phoneme queue (spkPhones/spkStress arrays)
              │
              ▼  SPK_Advance             (called once per audio sample from SPK_Fill)
formant-synthesized waveform sample
```

### Build-time: baking the dictionary (`tools/bake_speech_dict`)

`speech_dict.txt` isn't hand-written. It's generated from whatever words actually appear in the game's text, so the embedded dictionary stays small instead of shipping the entire ~130k-word CMU dictionary:

1. Renders `assets/gametext.txt` with `assets/gamevalues.ini` token substitution applied (the same substitution `GTEXT_Render$` does at runtime), so tokens like `{{emperor}}` resolve to their actual value before word extraction.
2. Strips block tags, `~XX` color codes, and applies the same contraction pre-pass `SPK_Say` uses at runtime (strip possessive `'s`, strip bare apostrophes). This has to match exactly, or a word baked one way won't match how `SPK_Say` looks it up at runtime.
3. Extracts every resulting word, looks each up in `assets/cmudict-0.txt` (the CMU Pronouncing Dictionary, ARPAbet format), and additionally tries a plural stem (`-S` / `-IES`) for words not found directly. The baked entry is the *stem's* pronunciation, since `SPK_Say`'s runtime plural fallback (below) needs the stem present.
4. Merges in `assets/custom_words.txt`, hand-written entries (in the same `WORD PH1 PH2 ...` format) for words the CMU dictionary doesn't have, mostly this game's invented proper nouns (`AIGASOL`, `THERACCOONBEAR`, etc).
5. **Fails the build** if any word has no pronunciation entry at all (not in CMU dict, no plural-stem match, no custom entry). This is what catches a newly-added line of dialogue with an unpronounceable made-up word before it ships.

Run it whenever `assets/gametext.txt` or `assets/gamevalues.ini` changes:

```bash
bash tools/bake_speech_dict
```

CI's `dict-check` job re-runs this and fails if `assets/speech_dict.txt` is stale. Commit the regenerated file.

### Startup: loading the dictionary

`speech_dict.txt` is embedded (`$EMBED:'assets/speech_dict.txt':'SPEECHDICT'`) and parsed by `SPK_LoadDict` into parallel arrays, sorted alphabetically by word (required, since `SPK_DictFind` binary-searches them).

### Runtime: text to phonemes (`SPK_Say`)

```basic
SPK_Say "Enemy fighters incoming."
```

- Strips punctuation into pause tokens (`.`/`!`/`?` → longer pause, `,`/`;`/`:`/` - ` → shorter pause) *before* stripping non-letters, so sentence and clause boundaries still get natural gaps.
- For each word: dictionary lookup; if not found, tries stripping a trailing `S` (and re-deriving the correct final-`S`/`Z` allophone from the stem's last phoneme) or `IES→Y`; if still not found, spells it letter-by-letter using `spkLetterSeq` (robotic-sounding, but never silently drops a word).
- Records word start/end boundaries in the phoneme queue (`spkWordStart`/`spkWordEnd`/`spkWordText$`) so the crawl UI can highlight the word currently being spoken.
- **Do not call `SPK_Say` with a string literal.** All spoken text must live in `gametext.txt` so `bake_speech_dict` can see it and bake the pronunciation. A literal string bypasses that entirely and will either fail to speak (unknown word gets spelled out) or, worse, appear to work locally and then break for anyone who rebuilds the dictionary.

### Runtime: phonemes to waveform (`SPK_Advance`)

Called once per output sample from the audio fill loop (wired in via `snd.bas`), so it has to be cheap: no trig, no allocation.

- Each of the 40 phonemes (39 ARPAbet + silence) has precomputed formant wavetables (`spkWaveLib`, built once by `SPK_BuildAllWaves` at `SPK_Init`, using additive sine harmonics shaped by resonant peaks at each phoneme's F1/F2/F3 frequencies, with three pitch variants for unstressed/primary/secondary stress). Building these at runtime per-phoneme would stall the real-time audio path; building them all upfront turns the hot path into a fast array copy.
- Vowels and sonorants read the wavetable directly. Fricatives and stops add or substitute high-pass-filtered noise (cutoff varies by place of articulation, e.g. alveolar `T` is hissier than bilabial `P`); stops have a silent closure phase before a burst.
- Diphthongs (`AY`, `EY`, `OW`, `AW`, `OY`) glide from an onset wavetable to a target vowel's wavetable over the phoneme's duration, rather than using a single fixed formant.
- **Coarticulation**: during a phoneme's 10 ms fade-in, if both it and the previous phoneme are voiced, the waveform crossfades from the previous phoneme's wavetable to the new one. This is what keeps voiced runs from sounding like disconnected clicks.
- `SPK_SyncToScroll(scrollPx, pxPerFrame)` adjusts `spkRateScale` so a queued utterance finishes roughly when the crawl text scrolls off-screen, clamped to 0.6x-1.2x to avoid audibly distorting phoneme quality.

## Public API

```basic
SPK_Init                          ' once at startup: builds wavetables, loads the dictionary
SPK_Say text$                     ' queue text for speech (text$ must come from gametext.txt)
SPK_SyncToScroll scrollPx, pxPerFrame   ' optional: match speech rate to crawl scroll speed
SPK_Advance                       ' once per audio sample; result lands in spkSampleOut
SPK_IsPlaying%()                  ' -1 while an utterance is still playing, 0 when done
SPK_CurWord$()                    ' word currently being spoken, "" between words (for UI highlight)
SPK_CurWordOcc%()                 ' 0-based occurrence index, for highlighting repeated words correctly
```

## Known limitations and gotchas

- **Coverage is closed-world by design.** Anything not baked into `speech_dict.txt` gets spelled out letter-by-letter. Jarring, but deliberate as a fail-safe rather than silence. The real fix for a bad-sounding word is always adding it to `assets/custom_words.txt` and re-baking, not special-casing it in code.
- **`bake_speech_dict`'s text-processing pre-pass must stay in sync with `SPK_Say`'s.** If one strips a character the other doesn't, words that look identical at bake time and runtime can end up mismatched.
- **Single active utterance.** `SPK_Say` resets the phoneme queue. Calling it again before `SPK_IsPlaying%()` returns 0 cuts off whatever was still being said.
- **Formant/duration tables are hand-tuned constants** (Peterson & Barney 1952 for vowels, Klatt 1980 approximations for consonants) baked directly into `SPK_Init`. Adjusting voice quality means editing those tables; there's no runtime configuration.

## Testing in isolation

There is no dedicated automated test for the synthesis path itself. The closest thing is `bake_speech_dict`'s build-time failure on missing pronunciations, which catches the most common real bug (new dialogue text with a word that can't be pronounced) before it ships. Run it after any `gametext.txt`/`gamevalues.ini` change:

```bash
bash tools/bake_speech_dict
```

Beyond that, verify audibly: build and run the game, trigger a crawl or callout, and listen. If you're changing formant/duration tables or coarticulation logic, there's no substitute for listening to the result.
