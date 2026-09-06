# qc_mags `fast_taxonomy` — rationale, benchmarks and validation

A three-line change to GTDB-Tk invocation that removes the pipeline's dominant
bottleneck without altering a single taxonomic call.

| | |
|---|---|
| Branch | `fast_gtdbtk` |
| Base | `qc_mags` v1.0.1 (as deployed at `/data/pam/installs/custom_installs/qc_mags/v1.0.1`) |
| GTDB-Tk | 2.7.2, GTDB r232 |
| Measured on | farm22, 2026-09-04 |
| Genomes compared fast vs upstream | **5,293** |
| Classification differences | **0** |

---

## 1. Why

GTDB-Tk is the slowest step in `qc_mags`, and upstream runs it with
`--place_species`. That flag forces every genome through pplacer's reference-tree
placement. Placement is expensive and almost entirely *fixed* cost: loading and
caching the class-level tree runs to ~50 GB of likelihood data, and GTDB-Tk
repeats it once per class-level tree — five or six times in a typical batch.

The resulting task asks for **8 cores and 64 GB**. On a busy farm that is close to
unschedulable, because memory rather than slots is the scarce resource. During
this work farm22 had 6,592 idle slots but only 17 of ~115 hosts with 32 GB free,
and at one point **zero** hosts could satisfy 64 GB plus 8 free processor units.

Hosts able to accept the task (measured, farm22):

| Labels | Mode | Eligible hosts |
|---|---|---|
| `cpu_2` / `mem_32` | fast, per-sample | **18** |
| `cpu_4` / `mem_50` | fast, batched | **18** |
| `cpu_8` / `mem_64` | upstream + scratch | 9 |
| `cpu_8` / `mem_120` | upstream, no scratch | 7 |

The key observation: **`--place_species` does not decide species assignment.**
GTDB-Tk's skani ANI screen does, and where the two disagree the ANI result wins.
Placement supplies a second opinion the final call never uses.

---

## 2. The change

```groovy
- label params.batch_size > 100 ? "cpu_64" : "cpu_8"
+ label params.fast_taxonomy ? (params.batch_size > 100 ? "cpu_4"  : "cpu_2")
+                            : (params.batch_size > 100 ? "cpu_64" : "cpu_8")

- label params.temp_file_storage ? "mem_64" : "mem_120"
+ label params.fast_taxonomy ? (params.batch_size > 100 ? "mem_50" : "mem_32")
+                            : (params.temp_file_storage ? "mem_64" : "mem_120")

+ place_flag = params.fast_taxonomy ? "" : "--place_species"
- gtdbtk classify_wf ... --place_species --cpus ${task.cpus} ...
+ gtdbtk classify_wf ... ${place_flag} --cpus ${task.cpus} ...
```

Three lines in `assorted-sub-workflows/qc_mags/modules/gtdbtk.nf`, plus
`fast_taxonomy` in `qc_mags.config`. 32 lines total.

Both label expressions are gated on `fast_taxonomy` **first**, so with the flag
`false` the generated `bsub` is byte-identical to upstream. `git diff master
fast_gtdbtk` is the complete change; `master` holds pristine v1.0.1.

---

## 3. Benchmark — batched

GTDB-Tk step in isolation, 16 cores requested for every run.

| Batch | Mode | Wall (min) | Cores used | Peak (GB) | Tree-placed | Identical |
|---|---|---|---|---|---|---|
| 500 | place | 132.6 | 4.80 | 34.8 | — | 500 / 500 |
| 500 | **fast** | **32.3** | 1.28 | 38.3 | 3 | |
| 1000 | place | 162.4 | 6.49 | 37.1 | — | 1000 / 1000 |
| 1000 | **fast** | **45.9** | 1.31 | 37.2 | 6 | |
| 1500 | place | 184.6 | 6.79 | 39.2 | — | 1500 / 1500 |
| 1500 | **fast** | **79.0** | 1.36 | 36.5 | 13 | |
| 2000 | place | 253.7 | 8.97 | 32.8 | — | 2000 / 2000 |
| 2000 | **fast** | **75.1** | 1.34 | 36.6 | 15 | |

**Speed-up 2.3–4.1×** across the range.

Two findings drive the label choices:

- Fast mode's memory is **flat across a 4× batch range** (38.3 → 36.6 GB), so
  the ~37 GB is a fixed reference-data load, not a per-genome cost. Batching is
  effectively free in memory terms.
- Fast mode uses **1.28–1.36 cores regardless of batch size**. The original
  `cpu_64` on the batched branch was 47× the measured need and was corrected.

The ANI miss rate held at **0.60–0.87%** across 5,000 genomes. That figure is the
entire basis of the speed-up, and the reason the default is dataset-dependent.

---

## 4. Benchmark — per-sample

Full pipeline, six samples, identical inputs.

| Sample | Genomes | Placed in fast | Fast | Upstream | Ratio |
|---|---|---|---|---|---|
| 51986_1#103 | 3 | 0 | 0.9 min | 48.0 min | **54×** |
| 51986_1#102 | 5 | 0 | 1.4 min | 64.5 min | **46×** |
| 51986_1#100 | 5 | 0 | 1.0 min | 68.9 min | **70×** |
| 51986_1#17 | 11 | 1 | 39.3 min | 60.8 min | 1.5× |
| 51986_1#49 | 8 | 1 | 31.5 min | 70.4 min | 2.2× |
| 51986_1#58 | 4 | 1 | 25.0 min | 68.0 min | 2.7× |
| **Total** | **36** | **3** | **99.2 min** | **380.6 min** | **3.84×** |

The saving splits sharply on one variable: **whether any genome in the sample
misses the ANI screen.** If none does, the sample never loads the reference tree
and finishes in about a minute — a 46–70× saving. If even one does, the fixed
cost is paid anyway and the saving falls to roughly 2×.

Per-sample runs therefore benefit most, having least to amortise the tree load
against. Memory was identical in both modes at 14.6–14.8 GB, giving `mem_32` a
2.2× margin.

---

## 5. Validation

The claim that matters is equivalence, not speed.

| Test | Genomes | Identical | Different |
|---|---|---|---|
| Batched 500 / 1000 / 1500 / 2000 | 5,000 | 5,000 | **0** |
| Per-sample benchmark | 36 | 36 | **0** |
| Production cohort (Sanger) | 257 | 257 | **0** |
| **Total** | **5,293** | **5,293** | **0** |

Reproducibility was checked separately: three independent fast-mode runs over the
same six samples agreed 36/36 with each other — on genome names and pass sets as
well as classifications.

### Why agreement holds despite internal disagreement

In place mode GTDB-Tk records whether tree topology and ANI concur. They
**disagreed on 12.9–14.8%** of genomes at every batch size — yet the final call
never changed, because ANI takes precedence for species assignment.

### The hard case

The *Bifidobacterium animalis* / `animalis_B` split is a near-threshold
discrimination within one species complex, and it defeated an earlier hand-rolled
skani workaround. Across **119 genomes** from that complex in the validation set,
fast mode partitioned them **exactly** as place mode did — at 2000 genomes, 34 as
`animalis_B` and 11 as plain `animalis`.

---

## 6. Production outcome

127 Sanger samples, same manifest, both configurations.

| | Upstream | `fast_taxonomy` |
|---|---|---|
| Samples completed | 60 of 127, then stalled | **127 of 127** |
| Elapsed | 32 h | **36 min** |
| GTDB-Tk compute | ~60 h projected | **200 min** |
| Mean per sample | 48–70 min | **1.6 min** |
| Errors | — | 0 |

Of 127 samples, **126 were resolved by the ANI screen alone**. A single sample
needed pplacer and consumed 27 of the 200 compute-minutes — roughly as much as
the other 126 combined. Under upstream settings every sample would have paid that
cost, which is why the original run managed 60 samples in 32 hours before
stalling with zero schedulable hosts.

---

## 7. Scope and caveats

**One dataset.** Every measurement comes from human and clinical isolates where
the ANI screen resolves 99.1–100% of genomes. For cohorts rich in novel or
under-represented taxa, more genomes fall through to the tree and both the
speed-up and the equivalence argument weaken.

**The upstream default should stay `false`.** This branch defaults to `true` for
team162 only. The 12.9–14.8% topology/ANI disagreement rate shows the tree
genuinely would say something different — it simply loses to ANI on this data.
**For an upstream MR, cut from commit `fc91621`**, where the flag still defaults
to `false`; later commits are team162 defaults and documentation.

**Wall-clock is queue-dependent.** The 36-minute production figure benefited from
a near-empty queue. The durable claims are the compute reduction and the
scheduling one, not elapsed time.

**Timing noise is large.** The same sample varied 24.3 vs 34.8 min on identical
input — about 40%. Single-run comparisons below ~1.5× are not meaningful here.

---

## 8. Rejected and recorded

### `--pplacer_cpus` — no effect

Tested on matched pairs across six samples. pplacer sat at **1.00–1.02 cores for
24–33 minutes** whatever the setting: it is strictly single-threaded and the flag
cannot change that. Results also crossed over between arms, well inside the noise
floor. The branch was not merged, so nobody tunes a knob that does nothing.

### Nextflow's resource fields are unusable on this container

Nextflow sums `peak_rss` and `%cpu` across the process tree. GTDB-Tk forks ~20
processes that memory-map the same reference package, so a task LSF measured at
**14.8 GB and 1.0 cores** was reported as **190 GB and 988%** — a 12.9×
overcount. A `%mem` above 100 is the giveaway. Every label decision here was
taken from `.command.log` instead.

---

## Documentation discrepancies noted in passing

Not addressed by this branch, but worth flagging:

- The README says "the `ani_screen` step is skipped", but the code passes
  `--place_species`, which does the opposite. GTDB-Tk 2.7.0 replaced
  `--skip_ani_screen` with `--place_species` and inverted the sense; the prose
  appears to describe pre-2.7 behaviour.
- The README references `release226`; the deployment uses `release232`.
- `qc_isolates/modules/gtdbtk.nf:40` still passes the deprecated
  `--skip_ani_screen` against a 2.7.2 container.

---

## Reproducing

```bash
git clone --branch fast_gtdbtk /lustre/scratch127/pam/teams/team162/ys4/qc_mags_fork
cd qc_mags_fork
git diff master fast_gtdbtk          # the complete change
```

Pinned to upstream v1.0.1, so rebasing onto a newer release is straightforward.
`git format-patch master..fast_gtdbtk` if you want it as a patch series.
