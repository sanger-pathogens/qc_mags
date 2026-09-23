process CHECKM2 {
    tag "${meta.ID}"
    label params.batch_size > 100 ? "cpu_32" : "cpu_4"
    // Small-run branch raised mem_8 -> mem_16. Measured on a 468-sample run:
    // PRE_CHECKM2 peaked at 8,256 MB and 422/468 tasks died with TERM_MEMLIMIT
    // at 8 GB. The overshoot is small but the failure is total, and because
    // REPORT joins on this output a failed task removes the whole sample from
    // the final report.
    label params.batch_size > 100 ? "mem_16" : "mem_16"
    label "time_queue_from_short"

    container  'quay.io/biocontainers/checkm2:1.0.2--pyh7cba7a3_0'

    publishDir mode: 'copy', path: "${params.outdir}/${qc_stage}/checkm2/", enabled: !(params.skip_raw_reports)

    input:
    tuple val(meta), path(fastas, stageAs: "fastas/*")
    val(qc_stage)

    output:
    tuple val(meta), path(report_tsv), emit: results

    script:
    report_tsv = "${meta.ID}_quality_report.tsv"
    """
    checkm2 predict -x ".${params.fasta_ext}" --threads ${task.cpus} --input fastas --output-directory checkm2 --database_path ${params.checkm2_db}

    # move the output file names to something slightly more descriptive including method
    mv checkm2/quality_report.tsv ${report_tsv}
    """
}