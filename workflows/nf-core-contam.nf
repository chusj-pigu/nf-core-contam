/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { FASTQC                    } from '../modules/nf-core/fastqc/main'
include { KRAKEN2_KRAKEN2           } from '../modules/nf-core/kraken2/kraken2/main'
include { MULTIQC                   } from '../modules/nf-core/multiqc/main'
include { SYLPH_PROFILE             } from '../modules/nf-core/sylph/profile/main'
include { SYLPHTAX_TAXPROF          } from '../modules/nf-core/sylphtax/taxprof/main'
include { WGET                      } from '../modules/nf-core/wget/main'
include { SYLPH_CACHE_DIRECTORY     } from '../modules/local/sylph/cache_directory/main'
include { SYLPH_CACHE_INSTALL       } from '../modules/local/sylph/cache_install/main'
include { SYLPH_PROFILE_IDS          } from '../modules/local/sylph/profile_ids/main'
include { SYLPHTAX_DOWNLOAD         } from '../modules/local/sylphtax/download/main'
include { SYLPHTAX_TAXPROF_IDS      } from '../modules/local/sylphtax/taxprof_ids/main'
include { VOYAGER_PROFILE           } from '../modules/local/voyager/profile/main'
include { HUMAN_READ_DEPLETION      } from '../subworkflows/local/human_read_depletion/main'
include { KRAKEN2_STANDARD_DATABASE } from '../subworkflows/local/kraken2_standard_database/main'
include { paramsSummaryMap          } from 'plugin/nf-schema'
include { paramsSummaryMultiqc      } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { softwareVersionsToYAML    } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { methodsDescriptionText    } from '../subworkflows/local/utils_nfcore_nf-core-contam_pipeline'

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
    def ch_human_reference = channel.value(
        [[id: params.genome ?: 'human'], file(params.fasta, checkIfExists: true)]
    )
    HUMAN_READ_DEPLETION(ch_samplesheet, ch_human_reference)
    def ch_unmapped_reads = HUMAN_READ_DEPLETION.out.unmapped_reads

    //
    // MODULE: Run FastQC
    //
    def ch_fastq_samples = ch_samplesheet.filter { _meta, reads ->
        reads.every { read -> read.name.matches('.*\\.f(ast)?q\\.gz$') }
    }
    FASTQC(ch_fastq_samples)
    ch_multiqc_files = ch_multiqc_files.mix(FASTQC.out.zip.map { _meta, file -> file })

    //
    // MODULE: Classify reads against a reusable Kraken2 standard database
    //
    def skip_kraken2 = params.skip_kraken2 instanceof String ? params.skip_kraken2.toBoolean() : params.skip_kraken2
    if (!skip_kraken2) {
        KRAKEN2_STANDARD_DATABASE()
        KRAKEN2_KRAKEN2(
            ch_unmapped_reads,
            KRAKEN2_STANDARD_DATABASE.out.db.first(),
            params.save_kraken2_output_fastqs,
            params.save_kraken2_read_assignments,
        )
        ch_multiqc_files = ch_multiqc_files.mix(KRAKEN2_KRAKEN2.out.report.map { _meta, file -> file })
    }

    //
    // MODULES: Profile reads with Sylph and add taxonomic abundances to MultiQC
    //
    if (!params.skip_sylph) {
        if (params.sylph_db_ids) {
            if (params.sylph_db || params.sylph_taxonomy) {
                error('Use either --sylph_db_ids with --sylph_db_cache_dir, or the manual --sylph_db and --sylph_taxonomy inputs, not both.')
            }
            if (!params.sylph_db_cache_dir) {
                error('--sylph_db_cache_dir is required when using --sylph_db_ids.')
            }

            SYLPH_CACHE_DIRECTORY(channel.value(params.sylph_db_cache_dir))
            def ch_sylph_cache_dir = SYLPH_CACHE_DIRECTORY.out.cache_dir
            def database_ids = params.sylph_db_ids.split(',').collect { identifier -> identifier.trim() }.findAll { identifier -> identifier }
            def database_specs = database_ids.collect { identifier -> sylphDatabaseSpec(identifier, params.sylph_db_cache_dir) }
            def cached_specs = database_specs.findAll { spec -> new File(spec.cache_path).isFile() && new File(spec.cache_path).length() > 0 }
            def missing_specs = database_specs - cached_specs
            def ch_cached_databases = channel.fromList(cached_specs).map { spec -> spec.cache_path }

            WGET(channel.fromList(missing_specs).map { spec -> [[id: spec.filename - '.syldb'], spec.url, 'syldb'] })
            SYLPH_CACHE_INSTALL(
                WGET.out.outfile
                    .combine(ch_sylph_cache_dir)
                    .map { meta, asset, cache_dir -> [meta, asset, "${cache_dir}/${meta.id}.syldb"] }
            )
            def ch_sylph_databases = ch_cached_databases
                .mix(SYLPH_CACHE_INSTALL.out.cache_path.map { _meta, cache_path -> cache_path })
                .map { cache_path -> file(cache_path, checkIfExists: true) }
                .collect()

            def taxonomy_dir = "${params.sylph_db_cache_dir}/taxonomy"
            def required_taxonomy_files = database_specs.collect { spec -> spec.taxonomy_file }.unique()
            def taxonomy_is_cached = required_taxonomy_files.every { taxonomy_file -> new File("${taxonomy_dir}/${taxonomy_file}").isFile() && new File("${taxonomy_dir}/${taxonomy_file}").length() > 0 }
            def ch_taxonomy_dir
            if (taxonomy_is_cached) {
                ch_taxonomy_dir = channel.value(taxonomy_dir)
            } else {
                SYLPHTAX_DOWNLOAD(ch_sylph_cache_dir.map { cache_dir -> ["${cache_dir}/taxonomy", required_taxonomy_files] })
                ch_taxonomy_dir = SYLPHTAX_DOWNLOAD.out.taxonomy_dir
            }

            SYLPH_PROFILE_IDS(ch_unmapped_reads, ch_sylph_databases)
            SYLPHTAX_TAXPROF_IDS(SYLPH_PROFILE_IDS.out.profile_out, channel.value(database_ids), ch_taxonomy_dir)
            ch_multiqc_files = ch_multiqc_files.mix(SYLPHTAX_TAXPROF_IDS.out.taxprof_output.map { _meta, file -> file })
        } else {
            if (!params.sylph_db) {
                error('A Sylph database is required. Set --sylph_db_ids with --sylph_db_cache_dir, provide a manual --sylph_db and --sylph_taxonomy pair, or use --skip_sylph.')
            }
            if (!params.sylph_taxonomy) {
                error('Sylph taxonomy metadata is required with --sylph_db. Use --sylph_db_ids to download official metadata, provide --sylph_taxonomy, or use --skip_sylph.')
            }

            def ch_sylph_db = channel.value(file(params.sylph_db, checkIfExists: true))
            def ch_sylph_taxonomy = channel.value(file(params.sylph_taxonomy, checkIfExists: true))
            SYLPH_PROFILE(ch_unmapped_reads, ch_sylph_db)
            SYLPHTAX_TAXPROF(SYLPH_PROFILE.out.profile_out, ch_sylph_taxonomy)
            ch_multiqc_files = ch_multiqc_files.mix(SYLPHTAX_TAXPROF.out.taxprof_output.map { _meta, file -> file })
        }
    }

    //
    // MODULE: Profile unmapped ONT reads with Voyager when a pre-built index is supplied.
    // Voyager is exploratory: missing or failed inputs produce a warning or failed-status row,
    // while Kraken2, Sylph, and MultiQC continue to run.
    //
    if (!params.skip_voyager) {
        if (!params.voyager_db) {
            log.warn("[${workflow.manifest.name}] Voyager was not run because --voyager_db was not provided")
        }
        else {
            def voyager_database = file(params.voyager_db)
            if (!voyager_database.exists()) {
                log.warn("[${workflow.manifest.name}] Voyager was not run because the index does not exist: ${params.voyager_db}")
            }
            else {
                VOYAGER_PROFILE(ch_unmapped_reads, channel.value(voyager_database))
                ch_multiqc_files = ch_multiqc_files.mix(VOYAGER_PROFILE.out.multiqc.map { _meta, file -> file })
            }
        }
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
            [process[process.lastIndexOf(':') + 1..-1], "  ${tool}: ${version}"]
        }
        .groupTuple(by: 0)
        .map { process, tool_versions ->
            tool_versions.unique().sort()
            "${process}:\n${tool_versions.join('\n')}"
        }

    def ch_collated_versions = softwareVersionsToYAML(ch_versions.mix(topic_versions.versions_file))
        .mix(topic_versions_string)
        .collectFile(
            storeDir: "${outdir}/pipeline_info",
            name: 'nf-core-contam_software_' + 'mqc_' + 'versions.yml',
            sort: true,
            newLine: true,
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

    emit:
    multiqc_report = MULTIQC.out.report.map { _meta, report -> [report] }.toList() // channel: /path/to/multiqc_report.html
    versions       = ch_versions // channel: [ path(versions.yml) ]
}

def sylphDatabaseSpec(database_id, cache_dir) {
    def databases = [
        'GTDB_r232': [filename: 'gtdb-r232-c200-dbv1.syldb', taxonomy_file: 'gtdb_r232_metadata.tsv.gz'],
        'GTDB_r226': [filename: 'gtdb-r226-c200-dbv1.syldb', taxonomy_file: 'gtdb_r226_metadata.tsv.gz'],
        'GTDB_r220': [filename: 'gtdb-r220-c200-dbv1.syldb', taxonomy_file: 'gtdb_r220_metadata.tsv.gz'],
        'GTDB_r214': [filename: 'v0.3-c200-gtdb-r214.syldb', taxonomy_file: 'gtdb_r214_metadata.tsv.gz'],
        'GlobDB_r232': [filename: 'globdb_r232_sylph_c200.syldb', taxonomy_file: 'globdb_r232_metadata.tsv.gz', url: 'https://fileshare.lisc.univie.ac.at/globdb/globdb_r232/taxonomic_profiling/globdb_r232_sylph_c200.syldb'],
        'GlobDB_r226': [filename: 'globdb_r226_sylph_c200.syldb', taxonomy_file: 'globdb_r226_metadata.tsv.gz', url: 'https://fileshare.lisc.univie.ac.at/globdb/globdb_r226/taxonomic_profiling/globdb_r226_sylph_c200.syldb'],
        'OceanDNA': [filename: 'OceanDNA-c200-v0.3.syldb', taxonomy_file: 'ocean_dna_metadata.tsv.gz'],
        'SoilSMAG': [filename: 'SMAG-c200-v0.3.syldb', taxonomy_file: 'soil_smag_metadata.tsv.gz'],
        'IMGVR_4.1': [filename: 'imgvr_c200_v0.3.0.syldb', taxonomy_file: 'IMGVR_4.1_metadata.tsv.gz'],
        'UHGV_default': [filename: 'uhgv_c200_dbv1.syldb', taxonomy_file: 'uhgv_default_metadata.tsv.gz'],
        'UHGV_ictv': [filename: 'uhgv_c200_dbv1.syldb', taxonomy_file: 'uhgv_ictv_metadata.tsv.gz'],
        'FungiRefSeq-latest': [filename: 'fungi-refseq-2025-10-11-c200-dbv1.syldb', taxonomy_file: 'fungi_refseq_2025-10-11_metadata.tsv.gz'],
        'FungiRefSeq-2024-07-25': [filename: 'fungi-refseq-2024-07-25-c200-dbv1.syldb', taxonomy_file: 'fungi_refseq_2024-07-25_metadata.tsv.gz'],
        'TaraEukaryoticSMAG': [filename: 'tara-eukmags-c200-v0.3.syldb', taxonomy_file: 'tara_SMAGs_metadata.tsv.gz'],
    ]
    if (!databases.containsKey(database_id)) {
        error("Unsupported Sylph database ID '${database_id}'. Supported IDs: ${databases.keySet().join(', ')}")
    }
    def database = databases[database_id]
    return [id: database_id, filename: database.filename, taxonomy_file: database.taxonomy_file, cache_path: "${cache_dir}/${database.filename}", url: database.url ?: "https://storage.googleapis.com/sylph-stuff/${database.filename}"]
}
