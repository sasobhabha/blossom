# Blossom: A Research-Grounded Composite Stress Indicator for watchOS

*A short technical paper describing the scoring algorithm behind the Blossom watch app.*

## Abstract

Blossom estimates psychological stress from sensors already available on Apple Watch and
communicates the result as a single colour on a lotus indicator and on a watch complication.
This paper describes the algorithm: a weighted composite of heart rate relative to a personal
baseline, heart rate variability (SDNN), respiratory rate, and sleep duration, each mapped to a
0–100 subscale whose anchor points are taken from published psychophysiology (heart-rate
response to standardized psychosocial stress, HRV normative tables, breathing–arousal coupling,
and a randomized sleep-restriction trial). Physical activity dampens the heart-rate term to
separate exertion from mental stress, and colour assignment follows experimental colour–emotion
research. The composite is a design construct — no such scale exists in the literature — but
every per-metric mapping is anchored to measured values. We state the formulas, the evidence
for each anchor, worked examples, and the method's limitations.

## 1. Introduction

Consumer wearables can detect the physiological signature of acute stress: elevated heart rate,
suppressed heart rate variability, altered breathing, and the downstream effects of short sleep.
Most implementations either report a single raw signal (which is ambiguous — a fast heart rate
may be stress or a staircase) or a black-box machine-learning score. Blossom takes a middle
path: a transparent, additive model with four signals, explicit weights, and anchor points that
can be traced to specific experimental results. The output is deliberately coarse — four
colour/status bands — because the intended use is a glanceable cue to breathe, not a clinical
measurement.

## 2. Signals

| Signal | HealthKit source | Window | Direction of stress |
|---|---|---|---|
| Heart rate | latest sample | ≤ 1 h | above personal baseline |
| HRV (SDNN) | latest sample | ≤ 7 days | lower |
| Respiratory rate | latest sample | ≤ 24 h | higher |
| Sleep | asleep categories (core/deep/REM/unspecified) | ≤ 24 h | shorter |
| Activity (dampener) | energy, steps, distance | ≤ 24 h | explains away HR rises |

Blood oxygen (SpO₂) is read for completeness but **not scored**: we found no validated mapping
from oxygen saturation to psychological stress; SpO₂ reflects oxygenation, not arousal.

## 3. Method

### 3.1 Personal baseline

Let *b* be the user's own average heart rate: the HealthKit 24-hour mean, falling back to
HealthKit's resting-HR estimate, then to the session mean of observed samples. Measuring HR
against *b* rather than a fixed constant makes the score self-calibrating and conservative —
"normal for you" scores zero.

### 3.2 Component scores (each clamped to [0, 100])

```
S_HR   = (HR − b) / 18 × 100                 (weight 0.40)
S_HRV  = (60 − SDNN_ms) / 40 × 100           (weight 0.30)
S_RR   = (RR − 12) / 18 × 100                (weight 0.15)
S_sleep = (7 − sleep_hours) / 4 × 100        (weight 0.15)
```

**Anchor rationale.**

- **Heart rate (+9 bpm → 50, +18 bpm → 100).** A validated psychosocial stressor (the group
  Trier Social Stress Test with COVID-era adaptations) raised heart rate by **9 bpm** alongside
  cortisol and self-report effects [1]; standard in-person TSST protocols produce larger rises,
  and TSST-type stressors reliably elevate heart rate at large effect sizes (d ≈ 0.85–0.98)
  [2–4]. Thus +9 bpm — a full, validated laboratory stress response — sits at the start of the
  "Moderate" band, and double that at "High".
- **HRV (60 ms → 0, 40 ms → 50, ≤ 20 ms → 100).** Heightened occupational and laboratory stress
  is associated with reduced HRV and parasympathetic activity (lower RMSSD/HF) [5,6]. Normative
  data show healthy short-term SDNN averaging 50 ms (range 32–93) and 24-hour SDNN < 50 ms
  classified as unhealthy [7]. The chosen linear map places the healthy mean near the calm/
  normal boundary and clearly pathological values at maximum.
- **Respiratory rate (12/min → 0, 30/min → 100).** Respiration is tightly coupled to arousal
  [8] and stress measurably shifts breathing frequency [9]; clinical normal is 12–20 breaths/min,
  and slow breathing below 10/min increases HRV [10,11]. The map flags sustained rates above the
  normal range (≥ ~24.6/min alone reads "High").
- **Sleep (7 h → 0, ≤ 3 h → 100).** In a randomized crossover trial, restricting sleep from
  7.4 h to 6.2 h significantly raised perceived stress and anxiety [12].

### 3.3 Activity dampening

```
A = mean(min(1, kcal/400), min(1, steps/8000), min(1, metres/5000))
S_HR' = S_HR × (1 − 0.35 × A)
```

Heart rate must be corrected for posture and movement to isolate the mental-stress component
("additional heart rate") [13]. A user who has been active receives up to 35 % less
heart-rate credit, so a post-workout pulse does not read as stress.

### 3.4 Aggregation

Missing metrics are treated as *no evidence*, never as zero: the weighted mean is taken over the
metrics actually present (weights renormalized). This is why a sleepless night with no wear does
not score maximum stress, and why the score responds as soon as any one signal appears.

### 3.5 Severity bands and colour

| Score | Status | Colour |
|---|---|---|
| < 30 | Calm | blue |
| 30 – 50 | Normal | green |
| 50 – 70 | Moderate | yellow |
| ≥ 70 | High | red |

Colour assignment follows experimental colour–emotion research: arousal rises from blue and
green toward red [14]; a 132-study systematic review (42,266 participants) associates blue,
green with positive low-arousal states, yellow/orange with high-arousal states, and red with
high-arousal and threat-related states [15]; red specifically cues threat avoidance [16]. The
green → yellow → red sequence is also the universally read severity ramp.

### 3.6 Alert policy

When the real-data score is ≥ 70 on two consecutive readings, at most once per 30 minutes, the
app notifies the user to breathe at 5–7 breaths/min — the resonance-frequency range shown to
increase vagally-mediated HRV [11].

## 4. Worked examples

All four metrics present:

| Profile | HR vs *b* | SDNN | RR | Sleep | Score | Colour |
|---|---|---|---|---|---|---|
| Relaxed | +3 | 50 | 14 | 7.5 h | ~7 | blue |
| Typical day | +6 | 45 | 17 | 6 h | ~33 | green |
| Lab-stress combo | +9 | 40 | 18 | 6 h | ~44 | green (top) |
| Clearly stressed | +12 | 35 | 20 | 5.5 h | ~58 | yellow |
| Strong stress | +15 | 32 | 22 | 5 h | ~70 | red |

Single-signal thresholds (only one metric available; weights renormalized):

| Signal alone | blue | green | yellow | red |
|---|---|---|---|---|
| HR vs baseline | <+5.4 bpm | +5.4–9 | +9–12.6 | ≥ +12.6 bpm |
| SDNN | >48 ms | 48–40 | 40–32 | ≤ 32 ms |
| Respiratory rate | <17.4/min | 17.4–21 | 21–24.6 | ≥ 24.6/min |
| Sleep | >5.8 h | 5.8–5 h | 5–4.2 h | <4.2 h |

Note that with all four signals present no single metric can reach red by itself (maximum
contributions are 40/30/15/15 points): yellow and red require corroboration.

## 5. Implementation notes

Heart rate streams via an anchored object query with a 3-second refresh; a full metric sweep
runs every 30 seconds; HealthKit background delivery with an observer query keeps the score
fresh while the app is off-screen. The score and colour are published to an App Group container
and pushed to a WidgetKit extension (watch Smart Stack / complication), reloading timelines
only when the severity band changes to respect widget refresh budgets. Processing is entirely
on-device; no data leaves the watch.

## 6. Limitations

- The composite weights and band edges are design choices; the composite itself has not been
  validated against a ground truth (e.g., experience-sampling self-reports).
- SDNN anchor values are drawn from 24-hour and short-term norms; Apple Watch reports short
  recordings, which are not interchangeable with 24-hour SDNN [7].
- No individual calibration of HRV anchors; young/fit users may sit near the healthy-range
  floor at rest, while older users may rarely reach high HRV scores.
- Single-metric episodes (e.g., poor sleep only) intentionally under-weight in composite mode.
- SpO₂ is excluded for lack of evidence, not because it is uninformative in general.

## 7. Future work

Calibrate HRV anchors per user longitudinally; include RMSSD alongside SDNN (the metric most
frequently associated with stress in the scoping review [6]); validate bands against
experience-sampling labels; explore electrodermal activity where available.

## References

1. Helminen EC & Scheer JR. Cardiovascular, self-report, and behavioral stress reactivity to the group-based TSST. PMID [36935021](https://pubmed.ncbi.nlm.nih.gov/36935021/).
2. Kirschbaum C et al. The Trier Social Stress Test. PMID [8255414](https://pubmed.ncbi.nlm.nih.gov/8255414/).
3. Helminen EC et al. Stress reactivity to the TSST in traditional and virtual environments: a meta-analytic comparison. PMID [33534392](https://pubmed.ncbi.nlm.nih.gov/33534392/).
4. Seddon JA et al. Meta-analysis of the TSST in eliciting physiological stress responses in children and adolescents. PMID [32305745](https://pubmed.ncbi.nlm.nih.gov/32305745/).
5. Järvelin-Pasanen S et al. Heart rate variability and occupational stress — systematic review. PMID [29910218](https://pubmed.ncbi.nlm.nih.gov/29910218/).
6. Immanuel S et al. Heart Rate Variability for Evaluating Psychological Stress Changes in Healthy Adults: A Scoping Review. PMID [37290411](https://pubmed.ncbi.nlm.nih.gov/37290411/).
7. Shaffer F & Ginsberg JP. An Overview of Heart Rate Variability Metrics and Norms. PMID [29034226](https://pubmed.ncbi.nlm.nih.gov/29034226/).
8. Kluger DS et al. A Dynamic Link between Respiration and Arousal. PMID [39379154](https://pubmed.ncbi.nlm.nih.gov/39379154/).
9. Buj C et al. Effect of simultaneous physical and auditory stressors on cardiorespiratory response. PMID [40234515](https://pubmed.ncbi.nlm.nih.gov/40234515/).
10. Zaccaro A et al. How Breath-Control Can Change Your Life: A Systematic Review on Psycho-Physiological Correlates of Slow Breathing. PMID [30245619](https://pubmed.ncbi.nlm.nih.gov/30245619/).
11. You M et al. Influence of Respiratory Frequency of Slow-Paced Breathing on Vagally-Mediated Heart Rate Variability. PMID [38063977](https://pubmed.ncbi.nlm.nih.gov/38063977/).
12. Benasi G et al. The effects of sustained mild sleep restriction on stress and distress among healthy adults. PMID [38342031](https://pubmed.ncbi.nlm.nih.gov/38342031/).
13. van de Ven SRB et al. Accelerometer-based heart rate adjustment for ambulatory stress research. PMID [39562517](https://pubmed.ncbi.nlm.nih.gov/39562517/).
14. Wilms L & Oberfeld D. Color and emotion: effects of hue, saturation, and brightness. PMID [28612080](https://pubmed.ncbi.nlm.nih.gov/28612080/).
15. Jonauskaite D & Mohr C. Do we feel colours? A systematic review of 128 years of psychological research linking colours and emotions. PMID [39806242](https://pubmed.ncbi.nlm.nih.gov/39806242/).
16. Buechner VL et al. Red — take a closer look. PMID [25254380](https://pubmed.ncbi.nlm.nih.gov/25254380/).
