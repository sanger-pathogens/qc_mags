def validateManifest(manifestFile, batchSize) {
    try {
        def file = new File(manifestFile)
        if (!file.exists()) throw new Exception("Manifest file not found: ${manifestFile}")

        def lines = file.readLines().findAll { it.trim() }   // ignore blank lines
        if (lines.size() < 2) throw new Exception("Manifest file is empty or has no data rows")

        def header = lines[0].split(',')*.trim()

        def idIndex = null
        if (batchSize == 0) {
            idIndex = header.indexOf('ID')
            if (idIndex == -1) throw new Exception("Manifest must contain an 'ID' column if not using batch processing")
        }
        
        def magsIndex = header.indexOf('mags_dir')
        if (magsIndex == -1) throw new Exception("Manifest must contain an 'mags_dir' column")

        def unexpectedColumns = header.findAll { !['ID', 'mags_dir'].contains(it) }
        if (unexpectedColumns) {
            log.warn("The following unexpected columns were found in the manifest: ${unexpectedColumns}")
        }

        def valid = 0
        def missing = []

        lines.drop(1).eachWithIndex { line, i ->
            def rowNum = i + 2   // line number in the file, counting the header
            def values = line.split(',', -1)*.trim()

            if (batchSize == 0 && !(values.size() > idIndex && values[idIndex])) {
                throw new Exception("Missing ID at line ${rowNum}")
            }
            if (values.size() <= magsIndex || !values[magsIndex]) {
                throw new Exception("Missing Directory at line ${rowNum}")
            }

            def mags_dir = new File(values[magsIndex])
            if (mags_dir.isDirectory()) {
                valid++
            } else {
                missing << "line ${rowNum}: ${mags_dir}"
            }
        }

        if (missing) {
            log.warn "${missing.size()} of ${valid + missing.size()} manifest entries have no directory on the filesystem and will be skipped:\n  " + missing.join('\n  ')
        }
        if (valid == 0) throw new Exception("None of the directories in the manifest exist")

        return file.absolutePath

    } catch (Exception e) {
        throw new Exception("Manifest validation failed:\n${e.message}")
    }
}