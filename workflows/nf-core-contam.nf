/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { FASTQC                 } from '../modules/nf-core/fastqc/main'
include { KRAKEN2_KRAKEN2        } from '../modules/nf-core/kraken2/kraken2/main'
include { MULTIQC                } from '../modules/nf-core/multiqc/main'
include { SYLPH_PROFILE          } from '../modules/nf-core/sylph/profile/main'
include { SYLPHTAX_TAXPROF       } from '../modules/nf-core/sylphtax/taxprof/main'
include { HUMAN_READ_DEPLETION   } from '../subworkflows/local/human_read_depletion/main'
include { KRAKEN2_STANDARD_DATABASE } from '../subworkflows/local/kraken2_standard_database/main'
include { paramsSummaryMap       } from 'plugin/nf-schema'
include { paramsSummaryMultiqc   } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { softwareVersionsToYAML } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { methodsDescriptionText } from '../subworkflows/local/utils_nfcore_nf-core-contam_pipeline'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow NF_CORE_CONTAM {

    take:
    ch_samplesheet // channel: samplesheet read in from --input
    multiqc_config
    multiqc_logo
    multiqc_methods_description
    outdir

    main:

    def ch_versions = channel.empty()
    def ch_multiqc_files = channel.empty()

    //
    // SUBWORKFLOW: Deplete reads that align to the human reference
    //
    def ch_human_reference = channel.value([
        [id: params.genome ?: 'human'],
        file(params.fasta, checkIfExists: true)
    ])
    HUMAN_READ_DEPLETION(ch_samplesheet, ch_human_reference)
    def ch_unmapped_reads = HUMAN_READ_DEPLETION.out.unmapped_reads

    //
    // MODULE: Run FastQC
    //
    def ch_fastq_samples = ch_samplesheet.filter { _meta, reads ->
        reads.every { read -> read.name.matches('.*\\.f(ast)?q\\.gz$') }
    }
    FASTQC(ch_fastq_samples)
    ch_multiqc_files = ch_multiqc_files.mix(FASTQC.out.zip.map{ _meta, file -> file })

    //
    // MODULE: Classify reads against a reusable Kraken2 standard database
    //
    if (!params.skip_kraken2) {
        KRAKEN2_STANDARD_DATABASE()
        KRAKEN2_KRAKEN2(
            ch_unmapped_reads,
            KRAKEN2_STANDARD_DATABASE.out.db.first(),
            params.save_kraken2_output_fastqs,
            params.save_kraken2_read_assignments
        )
        ch_multiqc_files = ch_multiqc_files.mix(KRAKEN2_KRAKEN2.out.report.map { _meta, file -> file })
    }

    //
    // MODULES: Profile reads with Sylph and add taxonomic abundances to MultiQC
    //
    if (!params.skip_sylph) {
        if (!params.sylph_db) {
            error('A Sylph database is required. Set --sylph_db to a pre-sketched *.syldb file or use --skip_sylph.')
        }
        if (!params.sylph_taxonomy) {
            error('Sylph taxonomy metadata is required. Set --sylph_taxonomy to the file matching --sylph_db or use --skip_sylph.')
        }

        def ch_sylph_db = channel.value(file(params.sylph_db, checkIfExists: true))
        def ch_sylph_taxonomy = channel.value(file(params.sylph_taxonomy, checkIfExists: true))

        SYLPH_PROFILE(ch_unmapped_reads, ch_sylph_db)
        SYLPHTAX_TAXPROF(SYLPH_PROFILE.out.profile_out, ch_sylph_taxonomy)
        ch_multiqc_files = ch_multiqc_files.mix(SYLPHTAX_TAXPROF.out.taxprof_output.map { _meta, file -> file })
    }

    //
    // Collate and save software versions
    //
    def topic_versions = channel.topic("versions")
        .distinct()
        .branch { entry ->
            versions_file: entry instanceof Path
            versions_tuple: true
        }

    def topic_versions_string = topic_versions.versions_tuple
        .map { process, tool, version ->
            [ process[process.lastIndexOf(':')+1..-1], "  ${tool}: ${version}" ]
        }
        .groupTuple(by:0)
        .map { process, tool_versions ->
            tool_versions.unique().sort()
            "${process}:\n${tool_versions.join('\n')}"
        }

    def ch_collated_versions = softwareVersionsToYAML(ch_versions.mix(topic_versions.versions_file))
        .mix(topic_versions_string)
        .collectFile(
            storeDir: "${outdir}/pipeline_info",
            name:  'nf-core-contam_software_'  + 'mqc_'  + 'versions.yml',
            sort: true,
            newLine: true
        )

    //
    // MODULE: MultiQC
    //
    ch_multiqc_files = ch_multiqc_files.mix(ch_collated_versions)
    def ch_summary_params = paramsSummaryMap(workflow, parameters_schema: "nextflow_schema.json")
    def ch_workflow_summary = channel.value(paramsSummaryMultiqc(ch_summary_params))
    ch_multiqc_files = ch_multiqc_files.mix(ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'))
    def ch_multiqc_custom_methods_description = multiqc_methods_description
        ? file(multiqc_methods_description, checkIfExists: true)
        : file("${projectDir}/assets/methods_description_template.yml", checkIfExists: true)
    def ch_methods_description = channel.value(methodsDescriptionText(ch_multiqc_custom_methods_description))
    ch_multiqc_files = ch_multiqc_files.mix(ch_methods_description.collectFile(name: 'methods_description_mqc.yaml', sort: true))
    MULTIQC(
        ch_multiqc_files.flatten().collect().map { files ->
            [
                [id: 'nf-core-contam'],
                files,
                multiqc_config
                    ? file(multiqc_config, checkIfExists: true)
                    : file("${projectDir}/assets/multiqc_config.yml", checkIfExists: true),
                multiqc_logo ? file(multiqc_logo, checkIfExists: true) : [],
                [],
                [],
            ]
        }
    )
    emit:multiqc_report = MULTIQC.out.report.map { _meta, report -> [report] }.toList() // channel: /path/to/multiqc_report.html
    versions       = ch_versions                 // channel: [ path(versions.yml) ]
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
