# NextflowTool: A Groovy library of helper functions for Nextflow pipelines 

A Groovy library of helper functions such as printing path-info logo or printing help messages from JSON schemas

## Using in your project

The library is currently just some Groovy source files. Therefore the easiest way to manage them is via [Git Submodules](https://git-scm.com/book/en/v2/Git-Tools-Submodules). To use them with nextflow, make a submodule directory inside your `lib` directory. Groovy classes placed in this directory are automatically imported into your test files' scope, so you can simply reference them as e.g. `NextflowTool`, with no need for an `import` line.

## Credit and Contact

This software is actively developed by the PaM Informatics team of the Parasites and Microbe Programme at the Wellcome Sanger Institute (Hinxton, UK).

This code was initially developed using a code foundation borrowed to [nf-co.re tooling code base](https://github.com/nf-core/rnaseq/tree/3.13.2/lib).

For any queries, use our helpdesk [request portal](https://jira.sanger.ac.uk/servicedesk/customer/portal/16) (for Sanger staff) or contact us at pam-informatics@sanger.ac.uk.

Copyright (C) 2023,2024 Genome Research Ltd.