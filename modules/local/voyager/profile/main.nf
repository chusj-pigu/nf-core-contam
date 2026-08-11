process VOYAGER_PROFILE {
    tag "${meta.id}"
    label 'process_medium'
    // Voyager is an exploratory corroboration tool. An unavailable database, container, or task must not stop the primary classifiers.
    label 'error_ignore'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://depot.galaxyproject.org/singularity/voyager:0.1.4--hdfd78af_0'
        : 'quay.io/biocontainers/voyager:0.1.4--hdfd78af_0'}"

    input:
    tuple val(meta), path(reads)
    path database

    output:
    tuple val(meta), path('*.voyager.json'), optional: true, emit: profile
    tuple val(meta), path('*.voyager_mqc.tsv'), emit: multiqc
    tuple val(meta), path('*.voyager*.log'), optional: true, emit: log
    tuple val("${task.process}"), val('voyager'), eval('voyager-cli -v 2>&1 | sed -nE "s/.*([0-9]+\\.[0-9]+\\.[0-9]+).*/\\1/p" | head -n 1'), topic: versions, emit: versions_voyager

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def profile = "${prefix}.voyager.json"
    def stdout = "${prefix}.voyager.stdout.log"
    def stderr = "${prefix}.voyager.stderr.log"
    """
    profile_status='failed'
    profile_message='Voyager did not produce a valid profile'

    if voyager-cli \\
        ${args} \\
        --index ${database} \\
        --input ${reads} \\
        --output ${profile} \\
        > ${stdout} \\
        2> ${stderr}; then
        if [ -s ${profile} ] && grep -q '"global"' ${profile} && grep -q '"genomes"' ${profile}; then
            profile_status='success'
            profile_message='completed'
        else
            profile_message='completed without a valid profile'
        fi
    else
        profile_exit=\$?
        profile_message="failed (exit \${profile_exit}); inspect ${stderr}"
    fi

    total_reads=0
    processed_reads=0
    mapped_reads=0
    hits=0
    if [ "\${profile_status}" = 'success' ]; then
        total_reads=\$(sed -nE 's/^[[:space:]]*"total_reads":[[:space:]]*([0-9]+).*/\\1/p' ${profile} | head -n 1)
        processed_reads=\$(sed -nE 's/^[[:space:]]*"processed_reads":[[:space:]]*([0-9]+).*/\\1/p' ${profile} | head -n 1)
        mapped_reads=\$(sed -nE 's/^[[:space:]]*"mapped_reads":[[:space:]]*([0-9]+).*/\\1/p' ${profile} | head -n 1)
        hits=\$(sed -nE 's/^[[:space:]]*"hits":[[:space:]]*([0-9]+).*/\\1/p' ${profile} | head -n 1)
    fi

    printf 'sample\\tstatus\\ttotal_reads\\tprocessed_reads\\tmapped_reads\\thits\\tmessage\\n' > ${prefix}.voyager_mqc.tsv
    printf '%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\n' '${meta.id}' "\${profile_status}" "\${total_reads:-0}" "\${processed_reads:-0}" "\${mapped_reads:-0}" "\${hits:-0}" "\${profile_message}" >> ${prefix}.voyager_mqc.tsv
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    cat <<'END_VOYAGER_PROFILE' > ${prefix}.voyager.json
    {"global":{"total_reads":0,"processed_reads":0,"mapped_reads":0,"hits":0},"genomes":{}}
    END_VOYAGER_PROFILE
    printf 'sample\\tstatus\\ttotal_reads\\tprocessed_reads\\tmapped_reads\\thits\\tmessage\\n' > ${prefix}.voyager_mqc.tsv
    printf '%s\\tsuccess\\t0\\t0\\t0\\t0\\tstub profile\\n' '${meta.id}' >> ${prefix}.voyager_mqc.tsv
    printf 'Voyager stub profile\\n' > ${prefix}.voyager.log
    """
}
