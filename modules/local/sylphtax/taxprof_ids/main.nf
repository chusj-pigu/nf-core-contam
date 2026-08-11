process SYLPHTAX_TAXPROF_IDS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconda::sylph-tax=1.9.0"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://depot.galaxyproject.org/singularity/sylph-tax:1.9.0--pyhdfd78af_0'
        : 'quay.io/biocontainers/sylph-tax:1.9.0--pyhdfd78af_0'}"

    input:
    tuple val(meta), path(sylph_results)
    val(taxonomy_ids)
    val(taxonomy_dir)

    output:
    tuple val(meta), path('*.sylphmpa'), emit: taxprof_output
    tuple val("${task.process}"), val('sylph-tax'), eval("sylph-tax --version 2>&1 | tail -1"), emit: versions_sylphtax, topic: versions

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def taxonomies = taxonomy_ids.join(' ')
    """
    sylph-tax --no-config --taxonomy-dir '${taxonomy_dir}' taxprof \\
        ${sylph_results} \\
        ${args} \\
        -t ${taxonomies}

    mv *.sylphmpa ${prefix}.sylphmpa
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.sylphmpa
    """
}
