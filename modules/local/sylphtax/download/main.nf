process SYLPHTAX_DOWNLOAD {
    tag 'taxonomy metadata'
    label 'process_single'
    executor 'local'

    conda "bioconda::sylph-tax=1.9.1"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://depot.galaxyproject.org/singularity/sylph-tax:1.9.1--pyhdfd78af_0'
        : 'quay.io/biocontainers/sylph-tax:1.9.1--pyhdfd78af_0'}"

    input:
    tuple val(taxonomy_dir), val(required_files)

    output:
    val(taxonomy_dir), emit: taxonomy_dir

    script:
    def required = required_files.collect { filename -> "'${taxonomy_dir}/${filename}'" }.join(' ')
    """
    mkdir -p '${taxonomy_dir}'
    lock_dir='${taxonomy_dir}/.download.lock'
    until mkdir "\$lock_dir" 2>/dev/null; do sleep 2; done
    trap 'rmdir "\$lock_dir"' EXIT
    normalize_globdb_r232() {
        # Sylph-tax 1.9.1 downloads GlobDB r232 under the official source
        # filename, while taxprof resolves the GlobDB_r232 identifier using
        # this canonical cache filename.
        if [ -s '${taxonomy_dir}/globdb_r232_taxonomy_sylph.tsv.gz' ] && [ ! -s '${taxonomy_dir}/globdb_r232_sylph_tax.tsv.gz' ]; then
            cp '${taxonomy_dir}/globdb_r232_taxonomy_sylph.tsv.gz' '${taxonomy_dir}/globdb_r232_sylph_tax.tsv.gz'
        fi
    }
    normalize_globdb_r232
    missing=false
    for taxonomy_file in ${required}; do
        [ -s "\$taxonomy_file" ] || missing=true
    done
    if [ "\$missing" = true ]; then
        sylph-tax --no-config --taxonomy-dir '${taxonomy_dir}' download
        normalize_globdb_r232
    fi
    """

    stub:
    def required = required_files.collect { filename -> "'${taxonomy_dir}/${filename}'" }.join(' ')
    """
    mkdir -p '${taxonomy_dir}'
    for taxonomy_file in ${required}; do
        printf 'stub taxonomy metadata\n' > "\$taxonomy_file"
    done
    """
}
