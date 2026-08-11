process SYLPH_PROFILE_IDS {
    tag "${meta.id}"
    label 'process_high'

    conda "bioconda::sylph=0.9.0"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://depot.galaxyproject.org/singularity/sylph:0.9.0--ha6fb395_0'
        : 'quay.io/biocontainers/sylph:0.9.0--ha6fb395_0'}"

    input:
    tuple val(meta), path(reads)
    path databases, arity: '1..*'

    output:
    tuple val(meta), path('*.tsv'), emit: profile_out
    tuple val("${task.process}"), val('sylph'), eval('sylph -V | sed "s/sylph //g"'), topic: versions, emit: versions_sylph

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def input = meta.single_end ? "-r ${reads}" : "-1 ${reads[0]} -2 ${reads[1]}"
    def database_args = databases instanceof List ? databases.join(' ') : databases
    """
    sylph profile \\
        -t ${task.cpus} \\
        ${args} \\
        ${database_args} \\
        ${input} \\
        -o ${prefix}.tsv
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.tsv
    """
}
