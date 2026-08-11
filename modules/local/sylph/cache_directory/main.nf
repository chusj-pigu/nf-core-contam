process SYLPH_CACHE_DIRECTORY {
    tag 'Sylph cache directory'
    label 'process_single'
    executor 'local'

    input:
    val cache_dir

    output:
    val(cache_dir), emit: cache_dir

    script:
    """
    mkdir -p '${cache_dir}'
    """
}
