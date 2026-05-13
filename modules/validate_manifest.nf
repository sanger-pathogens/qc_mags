def validateManifest(manifestFile, batchSize) {
    try {
        def file = new File(manifestFile)
        if (!file.exists()) throw new Exception("Manifest file not found: ${manifestFile}")

        def lines = file.readLines()
        if (lines.size() < 2) throw new Exception("Manifest file is empty or has no data rows")

        // Parse header
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

        // Process each line
        lines.drop(1).eachWithIndex { line, lineNum ->
            def values = line.split(',')*.trim()
            def mags_dir = new File(values[magsIndex])

            if (batchSize <= 0) {
                def id = values[idIndex]
                if (!id) throw new Exception("Missing ID at line ${lineNum+1}")
            }

            if (!mags_dir) throw new Exception("Missing Directory at line ${lineNum+1}")
            if (!mags_dir.exists()) throw new Exception("Directory does not exist at the given path '${mags_dir}' at line ${lineNum+1}")
        }

        // Return manifest path on success
        return file.absolutePath

    } catch (Exception e) {
        throw new Exception("Manifest validation failed:\n${e.message}")
    }
}
