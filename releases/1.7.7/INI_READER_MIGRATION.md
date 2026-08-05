# Proposed: typed INI readers for standalone SteamShell

**Status: scoped, not started.** This is a plan, not a record of work done.

## The problem

Standalone reads settings by composing three calls at each site:

```ahk
MouseHideDelay := ClampInt(ToInt(IniReadS("Timing","MouseHideDelay","1000"), 1000), 0, 60000)
```

That shape states the default **twice** — once as the `IniReadS` fallback used
when the key is absent, and once as the `ToInt` fallback used when the value is
present but unparseable. Nothing forces the two to agree.

There are **47** call sites in the full `ClampInt(ToInt(IniReadS(...)))` form,
out of **131** `IniReadS` sites overall.

This is not hypothetical. The August 2026 audit found three pairs that had
drifted apart:

| Key | Absent-key default | Unparseable-value fallback |
|---|---|---|
| `[Splash] Mute` | `false` | `true` |
| `[Splash] PlayFullDuration` | `true` | `false` |
| `[Splash] SafetyMaxMs` | `15000` | `60000` |

A user with a typo in `Mute=` got the opposite of the documented default, and a
typo in `SafetyMaxMs=` quadrupled the splash safety ceiling. All three are fixed,
and `Validate-SteamShell.ps1` now fails the build on any such pair.

## Why the current fix is the weaker one

The validator assertion **detects** the mistake. XFE's design makes it
**unrepresentable**:

```ahk
HeartbeatSeconds := ReadInt("Companion", "HeartbeatSeconds", 60, 5, 3600)
```

One default. Bounds are parameters, not a wrapping call. There is no second
place for a default to disagree with the first, so the bug cannot be written.
XFE has 149 call sites in this form and has never had this class of defect.

A validator assertion is a net that catches falls. The typed reader removes the
edge.

## The migration

Port XFE's four helpers (`SteamShell-XFE.ahk`, currently around line 545):

| Helper | Replaces |
|---|---|
| `ReadBool(section, key, fallback)` | `ToBool(IniReadS(s, k, "x"), y)` |
| `ReadInt(section, key, fallback, min, max)` | `ClampInt(ToInt(IniReadS(...), y), lo, hi)` |
| `ReadNumber(section, key, fallback, min, max)` | `ClampFloat(ToFloat(IniReadS(...), y), lo, hi)` |
| `ReadText(section, key, fallback := "")` | bare `IniReadS(s, k, "x")` |

They are small and already depend only on `ClampInt`/`ClampFloat`, which both
trees now share.

### Why this is its own pass

- **47 call sites in the tree that replaces the Windows shell.** A mistake in a
  bounds argument is a bad default that ships; a mistake in a section or key name
  is a setting that silently stops being read. Neither is caught by the syntax
  check — both compile perfectly.
- The rewrite is **not** purely mechanical. Standalone's `IniReadS` performs
  comment-stripping and quote-trimming (`CleanIniValue`) that XFE's `ReadText`
  does not. The helpers must adopt that behaviour or a class of existing INI
  files starts parsing differently. **This is the part to get right first.**
- Several sites have no bounds today (`ToInt` with no `ClampInt` wrapper).
  Migrating them means *choosing* bounds, which is a judgement call per setting,
  not a transformation.
- Some read into legacy-key fallback chains, e.g.
  `EnableMouseParkOnFocusChange` reads `EnableMouseParkEveryRefocus` first.
  Those need the old shape or an explicit legacy-aware variant.

### Suggested order

1. Add the four helpers with `CleanIniValue` semantics preserved. Add a unit-style
   assertion to `Validate-SteamShell.ps1` that they exist and route through
   `CleanIniValue`.
2. Migrate the 47 full-form sites first — they already have explicit bounds, so
   the transformation is closest to mechanical.
3. Run `Run-SteamShellValidation.ps1`. Nothing here changes behaviour, so a
   clean build plus an unchanged settings schema is the expected result.
4. Migrate the bounded-by-nothing sites individually, deciding bounds per key and
   recording them in `SteamShellSettings_SAMPLE.ini` comments.
5. Leave the legacy-chain sites last, or leave them alone.

### How to know it worked

- `Validate-SteamShell.ps1` still passes, including the default/fallback
  assertion — which should become **unreachable** rather than merely satisfied,
  since the pattern it matches will no longer exist. Consider replacing it with an
  assertion that the *old composed form* has no remaining call sites.
- Settings schema version does **not** change. This is a refactor of how values
  are read, not of what is stored.
- A settings file written by 1.7.5 loads identically afterwards. Worth checking
  by hand with a deliberately malformed value in each of the migrated sections.
