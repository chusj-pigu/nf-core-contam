/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Resolve a reusable Kraken2 standard database, rebuilding it only when necessary.
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { KRAKEN2_BUILDSTANDARD } from '../../../modules/nf-core/kraken2/buildstandard/main'

workflow KRAKEN2_STANDARD_DATABASE {

    main:
    def cached_db = standardKraken2Database(params.kraken2_db_cache_dir)
    def ch_db

    if (cached_db && !params.force) {
        log.info "Using cached Kraken2 standard database: ${cached_db}"
        ch_db = channel.value(cached_db)
    } else {
        if (params.force) {
            log.info "Rebuilding the Kraken2 standard database because --force was specified"
        } else {
            log.info "No complete Kraken2 standard database found in ${params.kraken2_db_cache_dir}; building one"
        }
        KRAKEN2_BUILDSTANDARD(true)
        ch_db = KRAKEN2_BUILDSTANDARD.out.db
    }

    emit:
    db = ch_db
}

/*
 * The three *.k2d files are the minimum files Kraken2 needs to open a database.
 * The upstream builder is published only after its task completes successfully.
 */
def standardKraken2Database(cache_dir) {
    if (!cache_dir) {
        error('A Kraken2 database cache is required. Set --kraken2_db_cache_dir to a writable shared directory.')
    }

    def db = java.nio.file.Paths.get(cache_dir.toString()).toAbsolutePath().normalize().resolve('kraken2-standard')
    def required_files = [
        'hash.k2d',
        'opts.k2d',
        'taxo.k2d'
    ]

    return java.nio.file.Files.isDirectory(db) && required_files.every { filename ->
        java.nio.file.Files.isRegularFile(db.resolve(filename))
    } ? db : null
}
