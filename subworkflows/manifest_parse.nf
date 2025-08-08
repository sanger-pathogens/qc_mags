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
        .set { fastas }

    emit:
    fastas
}

def parse_row(HashMap row) {
    def meta = [:]
    def fastas = null

    String fasta_ext = params.fasta_ext.replaceAll(/^\./, '')

    meta.ID = row.ID
    fastas = file("${row.mags_dir}/*.${fasta_ext}")

    return [meta, fastas]
}
