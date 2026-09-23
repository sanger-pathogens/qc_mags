process GUNC {
    tag "${meta.ID}"
    label params.batch_size > 100 ? "cpu_32" : "cpu_16"
    // Small-run branch raised mem_8 -> mem_16. Measured on a 468-sample run:
    // PRE_GUNC peaked at 9,711 MB and 464/468 tasks died with TERM_MEMLIMIT at
    // 8 GB. As with CheckM2, REPORT joins on this output, so each failure
    // silently drops a sample from the report.
    label params.batch_size > 100 ? "mem_32" : "mem_16"
    label "time_12"

    container  'quay.io/biocontainers/gunc:1.0.6--pyhdfd78af_0'

    publishDir mode: 'copy', path: "${params.outdir}/${qc_stage}/gunc/", enabled: !(params.skip_raw_reports)

    input:
    tuple val(meta), path(fastas, stageAs: "fastas/*")
    val(qc_stage)

    output:
    tuple val(meta), path(report_tsv), emit: results

    script:
    report_tsv = "${meta.ID}_gunc.tsv"
    """
    mkdir ${meta.ID}_gunc
    gunc run -r ${params.gunc_db} -d fastas --file_suffix ".${params.fasta_ext}" -o ${meta.ID}_gunc -t ${task.cpus}

    mv ${meta.ID}_gunc/GUNC.gtdb_95.maxCSS_level.tsv ${report_tsv}
    """
}