#!/usr/bin/env nextflow
// Copyright (C) 2024 Genome Research Ltd.

/*
========================================================================================
    HELP
========================================================================================
*/

def logo = NextflowTool.logo(workflow, params.monochrome_logs)

log.info logo

NextflowTool.commandLineParams(workflow.commandLine, log, params.monochrome_logs)


def printHelp() {
    NextflowTool.help_message("${workflow.ProjectDir}/schema.json", 
                               ["${workflow.ProjectDir}/assorted-sub-workflows/qc_mags/schema.json"],
    params.monochrome_logs, log)
}

/*
========================================================================================
    IMPORT MODULES/SUBWORKFLOWS
========================================================================================
*/

include { validateManifest } from './modules/validate_manifest.nf'

//
// SUBWORKFLOWS
//

include { MANIFEST_PARSE } from './subworkflows/manifest_parse.nf'

include { QC_MAGS } from './assorted-sub-workflows/qc_mags/qc_mags.nf'

/*
========================================================================================
    RUN MAIN WORKFLOW
========================================================================================
*/

workflow {
    if (params.help) {
        printHelp()
        exit 0
    }

    manifest = Channel.fromPath(
        validateManifest( params.manifest, params.batch_size )
    )

    MANIFEST_PARSE(manifest)
    | QC_MAGS
}

workflow.onComplete {
        NextflowTool.summary(workflow, params, log)
}
