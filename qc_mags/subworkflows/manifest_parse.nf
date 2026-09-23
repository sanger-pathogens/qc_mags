//
// Check input manifest and produce assembly channels
//

workflow MANIFEST_PARSE {
    take:
    manifest // file: /path/to/manifest.csv

    main:

    def counter = 0

    manifest
        .ifEmpty { exit 1, "File is empty / Cannot find file at ${manifest}" }
        .splitCsv(header:true, strip:true, sep:',')
        .map { row -> parse_row(row, counter++) }
        .transpose()
        .tap { all_fastas }
        .unique { meta, fasta -> fasta.toString() }
        .tap { deduped_fastas }
        .groupTuple()
        .set { fastas }

    all_fastas.count().combine(deduped_fastas.count()).subscribe { total, unique ->
        def removed = total - unique
        log.info "Checking manifest uniqueness: ${total} FASTAs found, ${removed} duplicates (identical paths) removed, ${unique} retained"
    }

    emit:
    fastas
}

def parse_row(HashMap row, int index) {
    def meta = [:]
    def fastas = null

    String fasta_ext = params.fasta_ext.replaceAll(/^\./, '')

    /*
        This is just a placeholder ID as if batch processing is not being used, 
        the ID column is not required.
    */
    meta.ID = row.ID ?: "sample_${index}"
    
    if (params.recursive) {
        fastas = [
            file("${row.mags_dir}/*.${fasta_ext}"),
            file("${row.mags_dir}/**/*.${fasta_ext}")
        ].flatten()
    } else {
        fastas = file("${row.mags_dir}/*.${fasta_ext}")
    }

    // Fail loudly on an extension mismatch instead of silently QC'ing nothing.
    //
    // fasta_ext defaults to "fa", but mags_maker writes its best_bins as
    // *.fasta. With the default, every sample from a mags_maker run matches
    // zero genomes, and the pipeline then runs to completion producing empty
    // reports without raising any error. This checks the directory for other
    // common FASTA extensions and, if the configured one finds nothing while
    // another finds genomes, stops with the exact flag to pass.
    //
    // It deliberately does not switch the extension automatically: fasta_ext
    // is interpolated into ~20 downstream commands (gtdbtk -x, checkm2 -x,
    // gunc --file_suffix, quast/seqkit globs, mdmcleaner renames), so changing
    // it per-sample would need every process to cope with mixed extensions.
    def found = (fastas instanceof List) ? fastas.findAll { it.exists() } : (fastas?.exists() ? [fastas] : [])
    if (found.isEmpty()) {
        def alternatives = ['fa', 'fasta', 'fna', 'fa.gz', 'fasta.gz', 'fna.gz'].findAll { it != fasta_ext }
        def hits = alternatives.collectEntries { ext ->
            def m = params.recursive ?
                [file("${row.mags_dir}/*.${ext}"), file("${row.mags_dir}/**/*.${ext}")].flatten() :
                [file("${row.mags_dir}/*.${ext}")].flatten()
            [(ext): m.findAll { it.exists() }.size()]
        }.findAll { k, v -> v > 0 }
        if (hits) {
            def best = hits.max { it.value }
            error "Sample '${meta.ID}': found 0 genomes matching *.${fasta_ext} in ${row.mags_dir}, " +
                  "but found ${hits.collect { k, v -> "${v} *.${k}" }.join(', ')}. " +
                  "Re-run with --fasta_ext ${best.key}. (mags_maker writes *.fasta; the default here is \"fa\".)"
        }
        log.warn "Sample '${meta.ID}': no genomes found in ${row.mags_dir} under any common FASTA extension"
    }

    return [meta, fastas]
}
