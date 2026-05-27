# QC MAGs

[![Nextflow](https://img.shields.io/badge/nextflow%20DSL2-%E2%89%A521.04.0-23aa62.svg?labelColor=000000)](https://www.nextflow.io/)
[![run with docker](https://img.shields.io/badge/run%20with-docker-0db7ed?labelColor=000000&logo=docker)](https://www.docker.com/)
[![run with singularity](https://img.shields.io/badge/run%20with-singularity-1d355c.svg?labelColor=000000)](https://sylabs.io/docs/)

[[_TOC_]]

## Pipeline overview

QC MAGs is a Nextflow DSL2 pipeline that assesses the quality of Metagenome-Assembled Genomes (MAGs). It is not suitable for isolate genomes; use [QC Isolates](../qc_isolates) for those.

![Workflow diagram](assets/qc_mags_workflow_diagram.drawio.png)

The pipeline performs the following steps:

1. **Taxonomic classification** — GTDBTk `classify_wf` classifies each MAG taxonomically (the `ani_screen` step is skipped).
2. **Pre-decontamination QC** — QUAST evaluates assembly statistics; CheckM2 predicts completeness and contamination; GUNC checks for chimerism.
3. **Decontamination** — MDMCleaner removes contaminant contigs from each MAG; seqkit removes contigs below the minimum length threshold.
4. **Post-decontamination QC** — QUAST, CheckM2, and GUNC are re-run on the filtered MAG FASTAs.
5. **Reporting** — a summary CSV is produced combining pre- and post-decontamination QC metrics and GTDBTk classification results.

## Usage

### Quickstart

#### From source code

1. Clone this repository (including submodules):

   ```bash
   git clone --recurse-submodules https://gitlab.internal.sanger.ac.uk/sanger-pathogens/pipelines/qc_mags.git
   cd qc_mags
   ```

2. To run with `docker`, use the `-profile docker` option:

   ```bash
   nextflow run main.nf \
       -profile docker \
       --manifest manifest.csv \
       --outdir my_output
   ```

   Other profiles are also supported (`singularity`).  
   :warning: If no profile is specified the pipeline will run with the Sanger HPC-specific configuration.

3. Once the run has finished, clean up intermediate files:

   ```bash
   rm -rf work .nextflow*
   ```

#### Using on the Sanger farm

First load the latest pipeline module:

```bash
module load qc_mags
```

Then run on the command line with `qc_mags <options>`. For instance, to see a help message:

```bash
qc_mags --help
```

Submit to LSF:

```bash
bsub -o output.o -e error.e -q oversubscribed -R "select[mem>4000] rusage[mem=4000]" -M4000 \
    qc_mags \
        --manifest manifest.csv \
        --outdir my_output
```

### Input

#### Manifest (`--manifest`)

A CSV file with per-sample paths to directories containing MAG FASTA files. Each row specifies a sample ID and the directory of bin FASTA files for that sample.

```
ID,BIN_DIR
sample1,/path/to/sample1/bins/
sample2,/path/to/sample2/bins/
```

Run `qc_mags --help` for the exact manifest format required by this pipeline version.

### Output

Results are written to `--outdir` (default: `./results`):

```
results/
  gtdbtk/
    <sample_ID>/                   # GTDBTk classification output
  preqc/
    quast/                         # QUAST pre-decontamination reports
    checkm2/                       # CheckM2 pre-decontamination reports
    gunc/                          # GUNC pre-decontamination reports
  decontaminated/
    <sample_ID>/
      <bin>.fa                     # Decontaminated, length-filtered MAG FASTAs
  postqc/
    quast/                         # QUAST post-decontamination reports
    checkm2/                       # CheckM2 post-decontamination reports
    gunc/                          # GUNC post-decontamination reports
  reports/
    summary.csv                    # Combined pre/post QC summary with taxonomy
```

### Parameters

**Database options**

| Option            | Type   | Default                                             | Description                                |
| ----------------- | ------ | --------------------------------------------------- | ------------------------------------------ |
| `--checkm2_db`    | `path` | `/data/pam/software/checkm2_db/uniref100.KO.1.dmnd` | Path to the CheckM2 Diamond database file. |
| `--gunc_db`       | `path` | `/data/pam/software/gunc/GTDB/gunc_db_gtdb95.dmnd`  | Path to the GUNC Diamond database file.    |
| `--mdmcleaner_db` | `path` | `/data/pam/software/mdmcleaner/v1`                  | Path to the MDMCleaner database directory. |
| `--gtdbtk_db`     | `path` | `/data/pam/software/GTDBTk/release226`              | Path to the GTDBTk database directory.     |

---

**Other options**

| Option                | Type      | Default   | Description                                                                                                 |
| --------------------- | --------- | --------- | ----------------------------------------------------------------------------------------------------------- |
| `--fasta_ext`         | `string`  | `fa`      | File extension for output FASTA files.                                                                      |
| `--min_contig`        | `integer` | `0`       | Minimum contig length (bp). Contigs below this threshold are removed after decontamination.                 |
| `--report_config`     | `path`    | (bundled) | JSON configuration file for the summary report.                                                             |
| `--autoqc_config`     | `path`    | `null`    | Optional JSON config specifying QC thresholds to flag passing MAGs. Use `"default"` for the bundled config. |
| `--skip_raw_reports`  | `boolean` | `false`   | Skip publishing raw tool reports; only the final summary CSV is published.                                  |
| `--temp_file_storage` | `string`  | `/tmp`    | Directory for GTDBTk temporary files. Options: `/tmp`, `/dev/shm`, or `null` (write to memory).             |
| `--temp_space`        | `string`  | `30GB`    | Amount of temporary storage to reserve for GTDBTk jobs on the HPC.                                          |
| `--batch_size`        | `integer` | `0`       | Number of MAGs to process per batch for tools that support batching. `0` batches per sample ID.             |

---

**Output options**

| Option              | Type      | Default     | Description                                           |
| ------------------- | --------- | ----------- | ----------------------------------------------------- |
| `--outdir`          | `path`    | `./results` | Directory where results are written.                  |
| `--recursive`       | `boolean` | `false`     | Search input directories recursively for FASTA files. |
| `--monochrome_logs` | `boolean` | `false`     | Output logs in plain ASCII.                           |

### Advanced usage

#### GTDBTk temporary storage

GTDBTk requires significant temporary disk space. By default `/tmp` is used. On the Sanger HPC, set `--temp_file_storage /dev/shm` for faster I/O. For large datasets, ensure enough space is available or set `--temp_space` appropriately.

#### Automatic QC filtering

Supply `--autoqc_config` with a JSON config to automatically flag MAGs that meet user-defined completeness/contamination thresholds. Use `--autoqc_config default` to apply the bundled default thresholds.

### Dependencies

All software dependencies are containerised. The following databases must be available locally (Sanger HPC defaults are pre-configured):

- CheckM2 Diamond database (`--checkm2_db`)
- GUNC Diamond database (`--gunc_db`)
- MDMCleaner database (`--mdmcleaner_db`)
- GTDBTk database (`--gtdbtk_db`)

## Software versions

| Software   | Version | Image                                |
| ---------- | ------- | ------------------------------------ |
| GTDBTk     | —       | `quay.io/biocontainers/gtdbtk:*`     |
| QUAST      | —       | `quay.io/biocontainers/quast:*`      |
| CheckM2    | —       | `quay.io/biocontainers/checkm2:*`    |
| GUNC       | —       | `quay.io/biocontainers/gunc:*`       |
| MDMCleaner | —       | `quay.io/biocontainers/mdmcleaner:*` |
| seqkit     | —       | `quay.io/biocontainers/seqkit:*`     |

See `assorted-sub-workflows/qc_mags/modules/` for pinned container versions.

## Troubleshooting

- **GTDBTk fails with out-of-disk-space**: ensure the `--temp_file_storage` directory has sufficient space. On the Sanger HPC, use `/dev/shm` or a scratch directory.
- **Database not found**: confirm that all database paths exist and are accessible. On the Sanger HPC, default paths are pre-configured.
- **Resuming a failed run**: add `-resume` to your command to restart from cached intermediate results.
- For further help, check `.nextflow.log` and the per-process logs in the `work/` directory.

## Issues and Contributions

If you find an issue with this pipeline, or would like to suggest an improvement, please log an issue or open a pull request on this repository.

If you are at Sanger and need internal support, you can raise an issue on the PAM Freshservice portal: https://sanger.freshservice.com/support/catalog/items/426
