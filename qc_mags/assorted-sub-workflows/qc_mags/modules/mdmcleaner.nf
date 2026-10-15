process MDMCLEANER {
    tag "${meta.ID}"
    label "cpu_16"
    label "mem_8"
    label "time_12"

    container  'quay.io/biocontainers/mdmcleaner:0.8.7--pyh7cba7a3_0'

    publishDir mode: 'copy', path: "${params.outdir}/mdmcleaner/"

    input:
    tuple val(group_key), val(meta), path(fasta)

    output:
    tuple val(group_key), val(meta), path("*.${output_fasta_ext}"), emit: results

    script:
    fasta_ext = params.fasta_ext.replaceAll(/^\./, '')
    output_fasta_ext = "${fasta_ext}.gz"
    """
    # MDMcleaner splits contig names at ':' when it matches rRNA hits back to contigs, so a name such as
    # '3300029572.a:Ga0244925_108424' (JGI/IMG style) raises KeyError and the genome is dropped by the
    # 'ignore' errorStrategy without any warning (305 El Mouali 2026 genomes, Oct 2026). Swap ':' for a
    # placeholder in a copy of the input, then restore it in the cleaned output, so contig names come out
    # exactly as they went in.
    mkdir -p header_safe
    if gzip -t ${fasta} 2>/dev/null; then
        zcat ${fasta} | sed '/^>/ s/:/__COLON__/g' | gzip > header_safe/${fasta}
    else
        sed '/^>/ s/:/__COLON__/g' ${fasta} > header_safe/${fasta}
    fi

    mdmcleaner set_configs --db_basedir ${params.mdmcleaner_db} --threads ${task.cpus}
    mdmcleaner clean -i header_safe/${fasta} -o mdmcleaner_output -t ${task.cpus} -c mdmcleaner.config --fast_run

    # Unconditional: a 'zcat | grep -q' test fails under pipefail (grep -q exits early, zcat gets SIGPIPE).
    for file in mdmcleaner_output/*/*.fasta.gz; do
        zcat "\$file" | sed '/^>/ s/__COLON__/:/g' | gzip > "\$file.tmp"
        mv "\$file.tmp" "\$file"
    done

    # Rename files to match desired extension as mdmcleaner is always fasta
    for file in mdmcleaner_output/*/*.fasta.gz; do
        new_name=\$(echo "\$file" | sed "s|\\.fasta\\.gz\$|.${output_fasta_ext}|")
        mv "\$file" "\$new_name"
    done

    mv mdmcleaner_output/*/*_filtered_kept_contigs.${output_fasta_ext} .
    """
}
// Lists the genomes that went into MDMCLEANER but came out with no cleaned genome. MDMCLEANER runs under
// errorStrategy 'ignore' after two retries, and an ignored genome simply disappears from post-QC with
// nothing in the report to say so. Writes report/mdmcleaner_skipped.tsv (always, header-only when none)
// and prints the count, which the workflow turns into a log warning.
process MDMCLEANER_AUDIT {
    executor 'local'

    publishDir mode: 'copy', path: "${params.outdir}/report/"

    input:
    path(sent)
    path(cleaned)

    output:
    path("mdmcleaner_skipped.tsv"), emit: skipped
    stdout emit: n_skipped

    script:
    """
    printf 'batch\\tgenome\\n' > mdmcleaner_skipped.tsv
    sort -u ${cleaned} > cleaned.sorted
    sort -u ${sent} | awk -F'\\t' 'NR==FNR {done[\$0]=1; next} !(\$0 in done)' cleaned.sorted - >> mdmcleaner_skipped.tsv
    printf '%s' \$(( \$(wc -l < mdmcleaner_skipped.tsv) - 1 ))
    """
}
