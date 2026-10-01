# D5 — Contrast audit over glass

WCAG 2.1 relative-luminance method, computed from the actual locked tokens
(`lib/design/colors.dart`, `lib/design/glass.dart`, `lib/design/components/aurora_background.dart`).

- Text targets: **4.5:1** (AA) for body·small text; large/hero text also held to 4.5:1.
- Icons / focus rings / boundaries: **3:1** (AA non-text).
- Glass is translucent, so text was measured against the **worst-case backdrop**: brightest
  card fill (light theme: white 16% over bg) and the brightest aurora blob core (55% primary)
  a card can park on. The no-blur fallback raises the fill by +6%, which only helps.
- Status chips: fill = tone 12%, border 24% over the card backdrop.

## Results (after fixes)

| Theme | Combination | Ratio | Verdict |
|---|---|---|---|
| light | textPrimary on aurora/bg | 17.48:1 | ✅ AA |
| light | textPrimary on glass (fill 16%) | 17.70:1 | ✅ AA |
| light | textPrimary, glass parked on 55% aurora core | 9.77:1 | ✅ AA |
| light | textSecondary on glass | 5.19:1 | ✅ AA |
| light | brandInk hero number (₹1,24,500) on glass | 4.86:1 | ✅ AA |
| light | white label on brandInk PrimaryButton | 5.19:1 | ✅ AA |
| light | successInk on 12% success chip | 5.09:1 | ✅ AA |
| light | warningInk on 12% warning chip | 5.00:1 | ✅ AA |
| light | errorInk on 12% error chip | 5.18:1 | ✅ AA |
| light | brand-chip text (primary→ink 25%) on 12% chip | 5.31:1 | ✅ AA *(fixed)* |
| light | profit text (successInk) on glass | 5.79:1 | ✅ AA *(fixed)* |
| light | focus ring (accent→ink 32%) vs glass | 4.26:1 | ✅ non-text *(fixed)* |
| dark | textPrimary on bg | 17.77:1 | ✅ AA |
| dark | textPrimary on glass (fill 10%) | 13.99:1 | ✅ AA |
| dark | textPrimary, glass parked on 55% aurora core | 5.09:1 | ✅ AA |
| dark | textSecondary on glass | 7.23:1 | ✅ AA |
| dark | brandInk hero number on glass | 5.13:1 | ✅ AA |
| dark | onPrimaryDark label on #818CF8 button | 5.84:1 | ✅ AA |
| dark | successInk on 12% success chip | 6.80:1 | ✅ AA |
| dark | warningInk on 12% warning chip | 7.02:1 | ✅ AA |
| dark | errorInk on 12% error chip | 4.63:1 | ✅ AA |
| dark | accent focus ring vs glass | 8.46:1 | ✅ non-text |
| dark | primary icon on 12% brand chip | 4.27:1 | ✅ non-text |

## First-pass failures → fixes (shipped)

| Where | Was | Fix |
|---|---|---|
| Brand chip text, light (`#6366F1` on 12% chip) | 3.62:1 ❌ | Chip text = primary pulled 25% toward ink → **5.31:1** (icon keeps raw primary, passes non-text 3:1) |
| Small profit text, light (`#16A34A` 12px) | 3.09:1 ❌ | Use `successInk` for the text (icons keep raw success) → **5.79:1** |
| Light focus ring (`#06B6D4` on glass) | 2.27:1 ❌ | Focus ring = accent pulled 32% toward ink (same hue, like all `ink()` tones) → **4.26:1** |
| Glass border vs flat bg, light (white 22%) | ~1:1 ❌ (boundary) | **Documented exception** — see below |

## Documented exception — glass card boundary vs flat background (light)

A white 22% hairline over `#F4F6FA` cannot reach 3:1 by design, nor can a 16% white fill.
This is the accepted nature of frosted glass; separation is instead provided by **three**
cues together: (1) the drop shadow (light) / primary glow + 1dp inner top-highlight (dark),
(2) the scrim (black 10% light, 38% dark) that darkens the card body, and (3) cards are
laid over the aurora background — against any blob (even the 55% core = 9.77:1 for text) the
card silhouette is clearly visible. The boundary is not the *only* means of identifying the
component (WCAG 1.4.11 applies to info needed to identify controls; the controls inside
carry their own ≥3:1 focus rings and ≥4.5:1 labels).

## Also validated

- Reduced-text-scale edge: all text styles scale to 200% without clipping (flexible layouts, no fixed text heights).
- Nothing relies on color alone: statuses = icon + text + tint; profit = sign + color + text; focus = 2dp ring (not color swap).
- Grain overlay (3% light / 4% dark) changes background luminance by <0.5% — measured deltas above remain valid.

*All goldens were re-rendered after the fixes; 25 tests pass.*
