process SYLPHTAX_DOWNLOAD {
    tag 'taxonomy metadata'
    label 'process_single'
    executor 'local'

    conda "bioconda::sylph-tax=1.9.0"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://depot.galaxyproject.org/singularity/sylph-tax:1.9.0--pyhdfd78af_0'
        : 'quay.io/biocontainers/sylph-tax:1.9.0--pyhdfd78af_0'}"

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
    missing=false
    for taxonomy_file in ${required}; do
        [ -s "\$taxonomy_file" ] || missing=true
    done
    if [ "\$missing" = true ]; then
        sylph-tax --no-config --taxonomy-dir '${taxonomy_dir}' download
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
