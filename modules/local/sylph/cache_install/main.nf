process SYLPH_CACHE_INSTALL {
    tag "${meta.id}"
    label 'process_single'
    executor 'local'

    input:
    tuple val(meta), path(asset), val(cache_path)

    output:
    tuple val(meta), val(cache_path), emit: cache_path

    script:
    def cache_directory = new File(cache_path).parent
    """
    mkdir -p '${cache_directory}'
    if [ ! -s '${cache_path}' ]; then
        temporary_path=\$(mktemp "${cache_path}.partial.XXXXXX")
        cp '${asset}' "\$temporary_path"
        mv -n "\$temporary_path" '${cache_path}' || true
        rm -f "\$temporary_path"
    fi
    """

    stub:
    def cache_directory = new File(cache_path).parent
    """
    mkdir -p '${cache_directory}'
    printf 'stub cache asset\n' > '${cache_path}'
    """
}
