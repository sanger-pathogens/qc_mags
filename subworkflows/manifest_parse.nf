//
// Check input manifest and produce assembly channels
//

workflow MANIFEST_PARSE {
    take:
    manifest // file: /path/to/manifest.csv

    main:
    manifest
        .ifEmpty { exit 1, "File is empty / Cannot find file at ${manifest}" }
        .splitCsv(header:true, strip:true, sep:',')
        .map { row -> parse_row(row) }
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

def parse_row(HashMap row) {
    def meta = [:]
    def fastas = null

    String fasta_ext = params.fasta_ext.replaceAll(/^\./, '')


    /*
        This is just a placeholder ID as if batch processing is not being used, 
        the ID column is not required.
    */
    meta.ID = row.ID ?: "sample_${counter++}"
    
    if (params.recursive) {
        fastas = [
            file("${row.mags_dir}/*.${fasta_ext}"),
            file("${row.mags_dir}/**/*.${fasta_ext}")
        ].flatten()
    } else {
        fastas = file("${row.mags_dir}/*.${fasta_ext}")
    }

    return [meta, fastas]
}
