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
3. **Decontamination** — MDMCleaner removes contaminant contigs from each MAG; seqkit subsequently removes contigs below the minimum length threshold.
4. **Post-decontamination QC** — QUAST, CheckM2, and GUNC are re-run on the filtered MAG FASTAs.
5. **Reporting** — a summary CSV is produced combining pre- and post-decontamination QC metrics and GTDBTk classification results.

## Usage

### Quickstart

#### From source code

1. Clone this repository (including submodules):

   ```bash
   git clone --recurse-submodules <repo-url>
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

3. Once the run has finished successfully and you have inspected the output, clean up intermediate files. The `work/` directory and `.nextflow.log` are useful for troubleshooting — do not delete them until you are satisfied the outputs are correct:

   ```bash
   rm -rf work .nextflow*
   ```

   Alternatively, use `nextflow clean` for more fine-grained control over which runs and intermediate files are removed.

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
ID,mags_dir
sample1,/path/to/sample1/bins/
sample2,/path/to/sample2/bins/
```

The `--recursive` flag can be used in conjunction with the manifest to search each listed directory, automatically discovering all MAGs beneath the specified root paths rather than only those at the top level. Duplicate MAGs resolved to the same path across multiple entries are deduplicated prior to processing. When using this option, specifying `--batch_size` is required to ensure MAG counts per batch remain within sensible bounds — see [Batching large runs](#batching-large-runs).

### Output

Results are written to `--outdir` (default: `./results`):

```
results/
  pre_qc/
    gtdbtk/
      <sample_ID>_gtdbtk_summary.tsv    # GTDBTk taxonomic classification summary (unless --skip_raw_reports)
    quast/
      <sample_ID>_pre_qc_quast_report.tsv   # QUAST pre-decontamination assembly statistics (unless --skip_raw_reports)
    checkm2/
      <sample_ID>_quality_report.tsv    # CheckM2 pre-decontamination completeness/contamination (unless --skip_raw_reports)
    gunc/
      <sample_ID>_gunc.tsv              # GUNC pre-decontamination chimerism report (unless --skip_raw_reports)
  mdmcleaner/
    <sample_ID>_filtered_kept_contigs.<ext>.gz    # MDMCleaner-decontaminated MAG FASTAs
  seqkit/
    cleaned_<bin>.<ext>               # Length-filtered MAG FASTAs (after --min_contig filtering)
  post_qc/
    quast/
      <sample_ID>_post_qc_quast_report.tsv  # QUAST post-decontamination assembly statistics (unless --skip_raw_reports)
    checkm2/
      <sample_ID>_quality_report.tsv    # CheckM2 post-decontamination completeness/contamination (unless --skip_raw_reports)
    gunc/
      <sample_ID>_gunc.tsv              # GUNC post-decontamination chimerism report (unless --skip_raw_reports)
  report/
    <sample_ID>_final_report.tsv        # Combined pre/post QC and taxonomy summary
    <sample_ID>_filter_summary.tsv      # Summary of contigs removed during filtering
  pass/                                 # Only produced when --autoqc_config is set
    fastas/
      <bin>.<ext>                       # FASTAs for MAGs passing the autoQC thresholds
    report/
      <filtered_report>.tsv             # Report rows for passing MAGs
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
| `--fasta_ext`         | `string`  | `fa`      | File extension for input and output FASTA files.                                                            |
| `--skip_raw_reports`  | `boolean` | `false`   | Skip publishing raw tool reports; only the final summary CSV is published.                                  |

---

**Logging options**

| Option              | Type      | Default | Description                 |
| ------------------- | --------- | ------- | --------------------------- |
| `--monochrome_logs` | `boolean` | `false` | Output logs in plain ASCII. |

### Advanced usage

#### Report configuration

A configuration file can be supplied to the `--report_config` option to customise the final (per-sample) report generated by the pipeline. In particular, it allows (per-tool) customization of the identity column (to join the tool report tables together) and extract particular columns from these reports. The following tool names are currently mandatory: `QUAST`, `GTDBTK`, `GUNC`, `CHECKM2` (NOTE: tool name must be uppercase). In the following example config block, we select 2 columns (`classification` and `closest_genome_reference`) to extract from the GTDB-Tk report and to use `user_genome` as the identity column:

```
"GTDBTK": {
    "id_column": "user_genome",
    "keep_columns": [
        "classification",
        "closest_genome_reference"
    ]
}
```

Please refer to the default [`report_config.json`](./assorted-sub-workflows/qc_mags/assets/report_config.json) for expected JSON structure.

NOTE: In addition to columns derived from the tool reports, the script includes 4 columns `preqc_genome_name`, `postqc_genome_name`, `sample_or_strain_name` and `genome_status`. These are currently all derived from filenames (at some point).

| column                | description                                                                              |
| --------------------- | ---------------------------------------------------------------------------------------- |
| preqc_genome_name     | Name of the input fasta file minus extension                                             |
| postqc_genome_name    | Name of the fasta file output after contig filtering minus extension                     |
| sample_or_strain_name | Name of the fasta file up to the last `_` character                                      |
| genome_status         | `mag` if the fasta file contains the string `mag` (lower/uppercase), `isolate` otherwise |

The default columns included in the final report are as follows:

_General_

- preqc_genome_name
- postqc_genome_name
- sample_or_strain_name
- genome_status

_CheckM2_

- checkm2_postqc_Completeness
- checkm2_postqc_Contamination
- checkm2_postqc_Genome_Size
- checkm2_preqc_Completeness
- checkm2_preqc_Contamination
- checkm2_preqc_Genome_Size

_GTDBTk_

- gtdbtk_classification
- gtdbtk_closest_genome_reference

_GUNC_

- gunc_postqc_n_contigs
- gunc_postqc_pass.GUNC
- gunc_preqc_n_contigs
- gunc_preqc_pass.GUNC

_QUAST_

- quast_preqc\_\# contigs
- quast_preqc_Largest contig
- quast_preqc_Total length
- quast_preqc_GC (%)
- quast_preqc_N50
- quast_preqc_N90
- quast_preqc_auN
- quast_preqc_L50
- quast_preqc_L90
- quast_preqc\_\# N's per 100 kbp
- quast_postqc\_\# contigs
- quast_postqc_Largest contig
- quast_postqc_Total length
- quast_postqc_GC (%)
- quast_postqc_N50
- quast_postqc_N90
- quast_postqc_auN
- quast_postqc_L50
- quast_postqc_L90
- quast_postqc\_\# N's per 100 kbp

A note on **number of contigs** metrics: QUAST "# contigs" reports all contigs (both in pre and post QC reports) whilst GUNC's "num_contigs" is defined as all contigs that contain a mapped gene.

Please see output reports for these individual tools to see which columns you can _add_ to your own configuration. Remove any by omitting them from your custom config.

If using `autoqc` ensure your report config includes the column you wish to filter on. See below for more information.

#### AutoQC configuration

It is also possible to automatically filter MAGs based on QC metrics produced in the summary report described in [Report configuration](#report-configuration).

To apply this function, you must enable AutoQC by supplying a configuration file path to `--autoqc_config` (config as described [here](./assorted-sub-workflows/mixed_input/README.md#filter_metadatapy)) or by supplying the string "default" so that the default [autoqc_config.tsv](./assorted-sub-workflows/qc_mags/assets/autoqc_config.tsv) is used.

The default AutoQC config's pass criteria are:

- Over 90% Completeness
- Under 5% Contamination
- Passes GUNC contamination checks

It is possible to add filtering rules to the autoqc config for columns\* within the report config. If using a custom report config you can customise your AutoQC config: for the column using the tool name (lowercase) and keep_column from the report config seperated by an underscore i.e. &lt;tool&gt;\_&lt;keep_column&gt;. Note that for adding filters based on QUAST, CheckM2 or GUNC you must specify whether to use preqc or postqc reports i.e. &lt;tool&gt;\_&lt;qc_stage&gt;\_&lt;keep_column&gt;, as shown in the [Report configuration](#report-configuration) section.

\*NOTE: Unfortunately QUAST report columns are not currently columns you can AutoQC on. This is an area for future development and should be possible in future versions.

Please note - if you add the parameter `--autoqc_config` but do not supply either a valid config file path or "default" the pipeline will error on not being able to find a config file to use.

#### Batching large runs

Many of the tools within the pipeline benefit from processing multiple MAGs simultaneously. To enable cross-sample batching, specify a `batch_size` using the flag:

```bash
--batch_size <INT>
```

This flag aggregates MAGs across samples into batches of N, with any remainder assigned to a final batch. For example, to define batches of 2000:

```bash
--batch_size 2000
```

Batch size involves a trade-off between throughput and resource usage. Larger batches improve computational efficiency but increase run-time per job, while smaller batches can reduce latency — particularly on an uncontested cluster — but at the cost of significantly higher memory overhead. Note that batches below ~1000 MAGs may incur disproportionate database loading overhead relative to actual QC compute time. A batch size of 1000–2000 MAGs is recommended for most use cases to strike a balance.

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

| Software   | Version | Image                                                     |
| ---------- | ------- | --------------------------------------------------------- |
| GTDBTk     | 2.7.2   | `quay.io/biocontainers/gtdbtk:2.7.2--pyhdfd78af_0`        |
| QUAST      | 5.3.0   | `quay.io/biocontainers/quast:5.3.0--py39pl5321heaaa4ec_0` |
| CheckM2    | 1.0.2   | `quay.io/biocontainers/checkm2:1.0.2--pyh7cba7a3_0`       |
| GUNC       | 1.0.6   | `quay.io/biocontainers/gunc:1.0.6--pyhdfd78af_0`          |
| MDMCleaner | 0.8.7   | `quay.io/biocontainers/mdmcleaner:0.8.7--pyh7cba7a3_0`    |
| seqkit     | 2.10.0  | `quay.io/biocontainers/seqkit:2.10.0--h9ee0642_0`         |

See `assorted-sub-workflows/qc_mags/modules/` for pinned container versions.

## Troubleshooting

- **GTDBTk fails with out-of-disk-space**: ensure the `--temp_file_storage` directory has sufficient space. On the Sanger HPC, use `/dev/shm` or a scratch directory.
- **Database not found**: confirm that all database paths exist and are accessible. On the Sanger HPC, default paths are pre-configured.
- **Resuming a failed run**: add `-resume` to your command to restart from cached intermediate results.
- For further help, check `.nextflow.log` and the per-process `.command.log` logs in the `work/` directory.

Sanger users may find [this page](https://ssg-confluence.internal.sanger.ac.uk/spaces/PaMI/pages/181078206/General+pipeline+info#Generalpipelineinfo-Troubleshootingafailedpipelinerunandsendingabugreport) useful for troubleshooting Nextflow pipeline runs.

## Issues and Contributions

If you find an issue with this pipeline, or would like to suggest an improvement, please log an issue or open a pull request on this repository.

If you are at Sanger and need internal support, you can raise an issue on the PAM Freshservice portal: https://sanger.freshservice.com/support/catalog/items/426
