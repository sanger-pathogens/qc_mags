#!/usr/bin/env python3

import argparse
import json
import logging
import sys
from pathlib import Path
from typing import Optional

import pandas as pd

JOIN_COLUMN_STEM = "genome_name"
JOIN_COLUMN = f"preqc_{JOIN_COLUMN_STEM}"


def setup_logging(log_file: str = "qc_merge.log"):
    logging.basicConfig(
        level=logging.INFO,
        handlers=[logging.StreamHandler(), logging.FileHandler(log_file, mode="w")],
        format="%(asctime)s - %(levelname)s - %(message)s",
    )
    logging.info("Logging initialized.")


def read_tsv(path: Path, name: str) -> pd.DataFrame:
    try:
        df = pd.read_csv(path, sep="\t")
        logging.info(f"{name} loaded successfully: {path}")
    except Exception as e:
        logging.error(f"Error reading {name} from {path}: {e}")
        sys.exit(1)
    return df


def read_config(path: Path) -> dict:
    try:
        with open(path) as f:
            config = json.load(f)
    except Exception as e:
        logging.error(f"Error reading configuration file {path}: {e}")
        sys.exit(1)
    try:
        validate_config(config)
    except InvalidConfig:
        logging.error(
            f"Invalid config structure detected in configuration file {path}: {e}"
        )
    return config


class InvalidConfig(ValueError):
    pass


def validate_config(config: dict) -> None:
    valid_tools = {"GUNC", "CHECKM2", "GTDBTK", "QUAST"}
    expected_tools = valid_tools & config.keys()
    unexpected_tools = set(config.keys()) - valid_tools
    if expected_tools == set():
        raise InvalidConfig(
            f"Config does not contain at least one valid tool: {valid_tools}"
        )
    if unexpected_tools != set():
        logging.warning(
            f"Config contains keys that were not expected (and are ignored): {unexpected_tools}"
        )
    for tool in expected_tools:
        missing_keys = {"id_column", "keep_columns"} - config[tool].keys()
        if missing_keys != set():
            raise InvalidConfig(
                f"Config is missing a mandatory key for tool '{tool}': {missing_keys}"
            )
    logging.info("Config passed validation")


def process_input_report(
    df: pd.DataFrame, config: dict, tool: str, qc_stage: Optional[str] = None
) -> pd.DataFrame:
    tool = tool.lower()
    columns = config[tool.upper()]["keep_columns"]
    rename_dict = {}
    if qc_stage is not None:
        assert qc_stage in ("preqc", "postqc")
        rename_dict[config[tool.upper()]["id_column"]] = (
            f"{qc_stage}_{JOIN_COLUMN_STEM}"
        )
    else:
        rename_dict[config[tool.upper()]["id_column"]] = JOIN_COLUMN
    for column in columns:
        if qc_stage is not None:
            rename_dict[column] = f"{tool}_{qc_stage}_{column}"
        else:
            rename_dict[column] = f"{tool}_{column}"
    return df.rename(columns=rename_dict)[rename_dict.values()]


def process_postqc_genome_name(df: pd.DataFrame) -> pd.DataFrame:
    new_df = df.copy()
    new_df[JOIN_COLUMN] = df[f"postqc_{JOIN_COLUMN_STEM}"].str.extract(
        r"cleaned_(.*)_filtered_kept_contigs"
    )
    return new_df


GENOME_TYPES = ("auto", "mag", "isolate")
COMPLETENESS_COLUMN = "checkm2_postqc_Completeness"
CONTAMINATION_COLUMN = "checkm2_postqc_Contamination"
QUALITY_COLUMN = "mimag_quality"
GUNC_COLUMN = "gunc_postqc_pass.GUNC"


def mimag_quality(completeness, contamination, gunc_pass=None) -> Optional[str]:
    """MIMAG tier from post-QC CheckM2 plus post-QC GUNC (the rRNA/tRNA criteria
    of the full MIMAG HQ standard are not assessed).
    HQ: completeness > 90, contamination < 5 and GUNC pass;
    MQ: completeness >= 50, contamination < 10 and GUNC not failed;
    otherwise LQ (a GUNC fail is always LQ). HQ needs an explicit GUNC pass, so a
    genome without a GUNC result is MQ at most. Empty if CheckM2 is missing.
    This is the team162 rule used by every downstream table (CHAIN master,
    package-qc-mags); before 2026-10-16 this column ignored GUNC and used >= 90."""
    if pd.isna(completeness) or pd.isna(contamination):
        return None
    g = "" if gunc_pass is None or (not isinstance(gunc_pass, str) and pd.isna(gunc_pass)) else str(gunc_pass).strip().lower()
    if g == "false":
        return "LQ"
    if completeness > 90 and contamination < 5 and g == "true":
        return "HQ"
    if completeness >= 50 and contamination < 10:
        return "MQ"
    return "LQ"


def add_mimag_quality(df: pd.DataFrame) -> pd.DataFrame:
    if COMPLETENESS_COLUMN in df.columns and CONTAMINATION_COLUMN in df.columns:
        comp = pd.to_numeric(df[COMPLETENESS_COLUMN], errors="coerce")
        cont = pd.to_numeric(df[CONTAMINATION_COLUMN], errors="coerce")
        if GUNC_COLUMN in df.columns:
            gunc = df[GUNC_COLUMN]
        else:
            logging.warning(f"{GUNC_COLUMN} not in report; no genome can be HQ (needs a GUNC pass)")
            gunc = [None] * len(df)
        df[QUALITY_COLUMN] = [mimag_quality(a, b, g) for a, b, g in zip(comp, cont, gunc)]
    else:
        logging.warning(
            f"{COMPLETENESS_COLUMN}/{CONTAMINATION_COLUMN} not in report; "
            f"{QUALITY_COLUMN} left empty"
        )
        df[QUALITY_COLUMN] = None
    return df


def enrich_fields(df: pd.DataFrame, genome_type: str = "auto") -> pd.DataFrame:
    df["sample_or_strain_name"] = (
        df[JOIN_COLUMN].str.rsplit("_", expand=True, n=1).loc[:, 0]
    )
    if genome_type == "auto":
        # Legacy heuristic: "MAG" anywhere in the name. Misfires on MAG sets
        # whose names do not contain it (e.g. mags_maker's <sample>_bin_N).
        df["genome_status"] = df[JOIN_COLUMN].apply(
            lambda x: "mag" if "MAG" in x.upper() else "isolate"
        )
    else:
        df["genome_status"] = genome_type
    df = add_mimag_quality(df)
    return df


def merge_all(*dfs: pd.DataFrame, genome_type: str = "auto") -> pd.DataFrame:
    df, other_dfs = dfs[0], dfs[1:]
    join_keys = [JOIN_COLUMN]
    for other_df in other_dfs:
        overlapping_cols = set(df.columns) & set(other_df.columns)
        cols_to_drop = overlapping_cols - set(join_keys)
        other_df_clean = other_df.drop(columns=cols_to_drop)
        df = df.merge(other_df_clean, on=join_keys, how="left")
    df = enrich_fields(df, genome_type)
    return df


def reorder_columns(df: pd.DataFrame) -> pd.DataFrame:
    priority_cols = [
        JOIN_COLUMN,
        f"postqc_{JOIN_COLUMN_STEM}",
        "sample_or_strain_name",
        "genome_status",
        QUALITY_COLUMN,
    ]
    other_cols = sorted([col for col in df.columns if col not in priority_cols])
    new_order = priority_cols + other_cols
    return df[new_order]


TAXONOMY_COLUMN = "gtdbtk_classification"


def check_taxonomy(df: pd.DataFrame) -> None:
    """Warn about genomes without a GTDB-Tk call; fail if NO genome has one.

    A few genomes without taxonomy are expected (e.g. a genome whose post-QC
    steps were dropped). Every genome in the batch lacking it means the
    GTDB-Tk output was not joined at all - an empty/missing summary or a join
    key mismatch (as happened when the cleaned_..._filtered_kept_contigs
    wrapper was not stripped, leaving 72/83 batches of a 468-sample run with no
    taxonomy). That must fail the task rather than publish a taxonomy-less
    report that looks complete.
    """
    if df.empty:
        logging.warning("Merged report has no genomes; skipping taxonomy check")
        return
    if TAXONOMY_COLUMN in df.columns:
        values = df[TAXONOMY_COLUMN]
        missing = values.isna() | (values.astype(str).str.strip() == "")
    else:
        missing = pd.Series(True, index=df.index)
    n_missing = int(missing.sum())
    if n_missing:
        logging.warning(
            f"{n_missing}/{len(df)} genomes lack {TAXONOMY_COLUMN}: "
            + ", ".join(df.loc[missing, JOIN_COLUMN].astype(str).head(20))
            + (" ..." if n_missing > 20 else "")
        )
    if n_missing == len(df):
        logging.error(
            f"ALL {len(df)} genomes lack {TAXONOMY_COLUMN}: the GTDB-Tk summary is "
            "empty or did not join on genome name. Refusing to write a report "
            "without taxonomy."
        )
        sys.exit(2)


def parse_args():
    parser = argparse.ArgumentParser(
        description="Merge GUNC, CheckM2 and post-QC metadata."
    )
    parser.add_argument(
        "--pre_qc_quast", type=Path, required=True, help="Path to pre-QC QUAST report TSV"
    )
    parser.add_argument(
        "--pre_qc_checkm2", type=Path, required=True, help="Path to pre-QC CheckM2 TSV"
    )
    parser.add_argument(
        "--pre_qc_gunc", type=Path, required=True, help="Path to pre-QC GUNC TSV"
    )
    parser.add_argument(
        "--post_qc_quast", type=Path, required=True, help="Path to post-QC QUAST report TSV"
    )
    parser.add_argument(
        "--post_qc_checkm2", type=Path, required=True, help="Path to post-QC CheckM2 TSV",
    )
    parser.add_argument(
        "--post_qc_gunc", type=Path, required=True, help="Path to post-QC GUNC TSV"
    )
    parser.add_argument(
        "--gtdbtk", type=Path, required=True, help="Path to GTDBTK TSV"
    )
    parser.add_argument(
        "--config", type=Path, required=True, help="Path to report configuration file"
    )
    parser.add_argument(
        "--output", type=Path, required=True, help="Output TSV path"
    )
    parser.add_argument(
        "--genome_type",
        choices=GENOME_TYPES,
        default="auto",
        help="genome_status for every genome: 'mag' or 'isolate', or 'auto' "
        "(default) for the name heuristic ('mag' if the name contains 'MAG')",
    )
    return parser.parse_args()


def main():
    setup_logging()
    args = parse_args()

    config = read_config(args.config)

    args_qc_stage = {
        "pre_qc_quast": ["preqc","quast"],
        "pre_qc_checkm2": ["preqc", "checkm2"],
        "pre_qc_gunc": ["preqc", "gunc"],
        "gtdbtk": [None, "gtdbtk"],
        "post_qc_quast": ["postqc", "quast"],
        "post_qc_checkm2": ["postqc", "checkm2"],
        "post_qc_gunc": ["postqc", "gunc"]
    }

    dfs = []
    for arg, qc in args_qc_stage.items():
        qc_stage = qc[0]
        tool = qc[1]
        df = read_tsv(vars(args)[arg], arg)
        df = process_input_report(df, config, tool, qc_stage)

        if qc_stage == "postqc":
            df = process_postqc_genome_name(df)
        elif tool == "gtdbtk":
            # GTDB-Tk runs on the POST-QC (MDMCleaner-cleaned) fastas, so its user_genome is
            # "cleaned_<name>_filtered_kept_contigs". With qc_stage None its id was being
            # renamed straight to JOIN_COLUMN without that wrapper stripped, while every other
            # report's key is the bare <name>. The left-join therefore never matched and
            # gtdbtk_classification came out EMPTY for every genome, silently, in every run.
            # Strip the wrapper here so the key matches. Genomes whose name does not carry the
            # wrapper are left unchanged.
            stripped = df[JOIN_COLUMN].str.extract(
                r"^cleaned_(.*)_filtered_kept_contigs$"
            ).loc[:, 0]
            df[JOIN_COLUMN] = stripped.fillna(df[JOIN_COLUMN])
        dfs.append(df)

    merged = merge_all(*dfs, genome_type=args.genome_type)
    merged = reorder_columns(merged)

    check_taxonomy(merged)

    merged.to_csv(args.output, sep="\t", index=False)
    logging.info(f"Merged QC report written to: {args.output}")


if __name__ == "__main__":
    main()
