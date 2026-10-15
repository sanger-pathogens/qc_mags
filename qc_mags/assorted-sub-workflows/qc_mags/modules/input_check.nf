// Checks every input genome before any QC step reads it, one task per batch.
// Some public collections ship genomes converted from GenBank with the '//' record terminator left between
// contigs (49 El Mouali 2026 genomes, Oct 2026). QUAST rejects such a file and then fails for the WHOLE batch,
// so pre- and post-QC QUAST, and with them the batch report, are lost for ~500 genomes at a time.
// - lines that are exactly '//' and blank lines are removed (they carry no sequence)
// - characters that are not IUPAC nucleotide codes are left as they are but reported, so a bad genome is
//   named instead of silently taking its batch down
// Every change or problem is one row of input_fasta_fixes.tsv; the workflow warns when it has any rows.
process INPUT_FASTA_CHECK {
    tag "${meta.ID}"
    label 'cpu_1'
    label 'mem_1'
    label 'time_1'

    input:
    tuple val(meta), path(fastas, stageAs: 'input/*')

    output:
    tuple val(meta), path('checked/*'),             emit: fastas
    path("${meta.ID}_input_fasta_fixes.tsv"),        emit: fixes

    script:
    """
    mkdir -p checked
    : > ${meta.ID}_input_fasta_fixes.tsv
    for f in input/*; do
        name=\$(basename "\$f")
        if gzip -t "\$f" 2>/dev/null; then cat_cmd="zcat"; else cat_cmd="cat"; fi
        \$cat_cmd "\$f" | awk -v batch="${meta.ID}" -v name="\$name" -v fixes="${meta.ID}_input_fasta_fixes.tsv" '
            \$0 == "//" { slash++; next }
            /^[[:space:]]*\$/ { blank++; next }
            /^>/ { print; next }
            { if (\$0 ~ /[^ACGTNRYKMSWBDHVacgtnrykmswbdhv]/) bad++; print }
            END {
                if (slash) printf "%s\\t%s\\tremoved_double_slash_lines\\t%d\\n", batch, name, slash >> fixes
                if (blank) printf "%s\\t%s\\tremoved_blank_lines\\t%d\\n",        batch, name, blank >> fixes
                if (bad)   printf "%s\\t%s\\tWARNING_non_nucleotide_characters\\t%d\\n", batch, name, bad >> fixes
            }' > "checked/\$name.tmp"
        if [ "\$cat_cmd" = "zcat" ]; then gzip -c "checked/\$name.tmp" > "checked/\$name"; rm "checked/\$name.tmp"
        else mv "checked/\$name.tmp" "checked/\$name"; fi
    done
    """
}
