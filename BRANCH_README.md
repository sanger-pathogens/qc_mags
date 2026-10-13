# `fast_gtdbtk` — GTDB-Tk taxonomy mode for qc_mags

Fork of **qc_mags v1.0.1** (as deployed at
`/data/pam/installs/custom_installs/qc_mags/v1.0.1`).

## What it changes

Adds `params.fast_taxonomy`, controlling whether GTDB-Tk is forced to place every
genome in the pplacer reference tree.

| | `fast_taxonomy = true` | `fast_taxonomy = false` |
|---|---|---|
| flag passed | *(none)* | `--place_species` |
| genomes matched by skani ANI screen | assigned from the match | **also** placed in tree (redundant) |
| genomes with no ANI match | **placed in tree** | placed in tree |
| unbatched resource ask | `cpu_2` / `mem_32` | `cpu_8` / `mem_64` |

GTDB-Tk ≥2.7 runs a skani ANI screen against all GTDB references before any
placement. Upstream qc_mags passes `--place_species` unconditionally, forcing
pplacer even where skani has already assigned a species. This branch makes that
optional.

**Genomes without an ANI match are still placed in the tree in both modes.**
`fast_taxonomy` only skips placement that skani has already made redundant — it
is not a reduced-accuracy mode.

## Defaults, and why they differ

- **Upstream / MR proposal:** `fast_taxonomy = false` — behaviour unchanged, opt-in.
  Cut an MR from commit `fc91621` for this form.
- **This branch (team162):** `fast_taxonomy = true`.

team162 workflows are predominantly **human gut and clinical** cohorts, where
almost all recovered MAGs match an existing GTDB species representative. For that
input, forced tree placement is wasted work on ~99% of genomes. Teams working on
under-characterised environments (soil, marine, non-human hosts) should set
`fast_taxonomy = false`, where a much larger fraction genuinely needs placement.

## Evidence (Sanger + NCL cohorts, 4,190 MAGs, GTDB r232)

- **4,165 / 4,190 (99.4%)** assigned by the ANI screen; **25** required placement
- taxonomy **identical** to `--place_species` on every genome compared
- the 25 unmatched genomes were still placed, resolving to genus with no species
- GTDBTK per-sample task measured at **1.0–1.8 cores, ~15 GB peak** — against
  `cpu_8` / `mem_64` reserved
- median sample = 4–5 genomes (max 19); no sample in either cohort exceeded 50

## Why it matters: scheduling, not runtime

On an idle farm this saves ~20 minutes on a multi-hour run — GUNC and MDMcleaner
dominate the critical path, not GTDB-Tk. The real benefit is **schedulability**:
during farm contention the 8-core/64 GB task sat unschedulable for 30 hours while
1-core jobs ran normally. A 2-core/32 GB task gets a slot when an 8-core/64 GB one
does not.

## Usage

```bash
nextflow run <fork>/qc_mags/main.nf --manifest m.csv --outdir out --autoqc_config default
# fast mode is the default on this branch; to force upstream behaviour:
#   --fast_taxonomy false
```

Do **not** pass `-profile <name>` alone: the LSF executor config lives in the
generic config's `standard` profile, so naming another profile silently disables
LSF and runs everything on the submit host. Use `-c extra.config` instead, which
is additive.

## Maintenance

Pinned to upstream v1.0.1. `master` holds the pristine baseline, so
`git diff master fast_gtdbtk` is the full patch and rebasing onto a newer
upstream release is straightforward.

## Rejected: `--pplacer_cpus`

A `--pplacer_cpus` parameter was tried, on the theory that pplacer was the
bottleneck and could be given more threads. It was tested on six samples in
matched pairs and **rejected as a no-op**; the test branch was deleted. It should
not be reintroduced.

Measured, LSF-authoritative (`.command.log`, not Nextflow's trace):

| sample | tree-placed | `--pplacer_cpus 1` | `--pplacer_cpus N` |
|--------|-------------|--------------------|--------------------|
| #103   | 0           | 0.6 min / 1.23 cores | 0.6 min / 1.28 cores |
| #102   | 0           | 1.2 min / 1.31       | 0.8 min / 1.28       |
| #100   | 0           | 0.8 min / 1.21       | 0.9 min / 1.24       |
| #17    | 1           | 24.3 min / **1.00**  | 34.8 min / **1.02**  |
| #49    | 1           | 32.7 min / **1.01**  | 26.1 min / **1.01**  |

pplacer sits at exactly 1.00-1.02 cores for 24-33 minutes regardless of the
setting: it is strictly single-threaded and the flag cannot change that. The
per-sample results also cross over (#17 faster with 1 CPU, #49 faster with N),
and #17 varied 24.3 vs 34.8 min on identical input - so host variance (~40%)
exceeds any effect the flag could have.

**Caution for future benchmarking on this container:** Nextflow's `peak_rss` and
`%cpu` are both unreliable here. It sums across the process tree, and GTDB-Tk
forks ~20 processes that mmap the same reference package, so a task LSF measured
at 14.8 GB / 1.0 cores was reported as 190 GB / 988%. A `%mem` above 100 is the
giveaway. Use `.command.log` for all label decisions.

## skani 0.4.0 for the GTDB-Tk ANI screen

`params.gtdbtk_skani_bin` (default
`/lustre/scratch127/pam/teams/team162/shared_scratch/software/skani/0.4.0/skani`) is
bind-mounted over the GTDB-Tk 2.7.2 container's bundled skani 0.3.1. The container
is unchanged; `--gtdbtk_skani_bin null` restores the bundled binary.

No new skani database is needed. skani 0.4.0 reads the r232 GTDB-Tk package's
consolidated database (`skani/database`, 199,923 sketches) as-is. The standalone
`skani_gtdb_r232-v0.4` download on the skani wiki is a separate database and is
not used by GTDB-Tk.

Validation (2026-10-13, 40 Prevotella-panel genomes, `classify_wf` fast mode):

- ANI screen: 38/38 genomes classified by both versions with identical reference
  genome, ANI, AF and species; the "other related references" field holds the same
  entries in a different order. skani step 77 s (0.4.0) vs 86 s (0.3.1).
- Final 0.4.0 calls for those 38 equal the 0.3.1 ANI-screen calls (38/38).
- Real qc_mags run with this config: GTDBTK task logged
  `Calculating all vs all ANI with skani v0.4.0` and exited 0.
