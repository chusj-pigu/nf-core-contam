/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Align reads to the human reference and retain only primary unmapped reads.
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { MINIMAP2_ALIGN } from '../../../modules/nf-core/minimap2/align/main'
include { SAMTOOLS_VIEW } from '../../../modules/nf-core/samtools/view/main'
include { SAMTOOLS_FASTQ } from '../../../modules/nf-core/samtools/fastq/main'

workflow HUMAN_READ_DEPLETION {

    take:
    reads
    reference

    main:
    def ch_minimap_reads = reads.map { meta, read_files ->
        def bam_input = read_files.size() == 1 && read_files[0].name.matches('.*\\.(bam|sam|cram)$')
        [meta, bam_input ? read_files[0] : read_files]
    }
    MINIMAP2_ALIGN(
        ch_minimap_reads,
        reference,
        true,
        [],
        false,
        false
    )

    SAMTOOLS_VIEW(
        MINIMAP2_ALIGN.out.bam.map { meta, bam -> [meta, bam, []] },
        channel.value([[:], [], []]),
        channel.value([[:], []]),
        channel.value([[:], []]),
        []
    )

    SAMTOOLS_FASTQ(SAMTOOLS_VIEW.out.bam, false)

    emit:
    aligned_bam   = MINIMAP2_ALIGN.out.bam
    unmapped_bam  = SAMTOOLS_VIEW.out.bam
    unmapped_reads = SAMTOOLS_FASTQ.out.other
}
