rule star_index:
    input:
        fasta = config["ref"]["fasta"] if config["ref"]["fasta"] else "-"
    output:
        directory(config["ref"]["idx"])
    threads: 
        get_resource("star_index","threads")
    resources:
        mem_mb=get_resource("star_index","mem_mb"),
        walltime=get_resource("star_index","walltime")
    params:
        extra = ""
    log:
        f"{LOGDIR}/star_index/index.log"
    wrapper:
        "v3.7.0/bio/star/index"

def input_merge(wildcards):  
    return list(units.loc[(wildcards.sample), "fq" + wildcards.group])

rule merge:
    input:
        input_merge
    output:
        f"{OUTDIR}/merged/{{sample}}.r{{group}}.fastq.gz"
    log:
        f"{OUTDIR}/merge/{{sample}}.r{{group}}.log"
    benchmark:
        f"{OUTDIR}/merge/{{sample}}.r{{group}}.bmk"
    threads: get_resource("merge","threads")
    resources:
        mem_mb=get_resource("merge","mem_mb"),
        walltime=get_resource("merge","walltime")
    shell:"""
        cat {input} > {output} 2> {log}
    """

def input_star(sample,group):
    '''call the merge rule if there's more than one fastq, otherwise return the fastq directly'''
    fastqs = list(units.loc[(sample), f"fq{group}"])
    if len(fastqs) == 1:
        return fastqs[0]
    else:
        return f"{OUTDIR}/merged/{sample}.r{group}.fastq.gz"


def extra_params(wc):
    if config["technology"] == "10x":
        ver = config["technology_version"]
        extra="--sjdbGTFfile {} --soloCBwhitelist {} {}".format(config["ref"]["annotation"], config["whitelist"], config["parameters"]["star"]["10x"][ver])
        return extra
    elif config["technology"] == "drop-seq":
        extra = "--sjdbGTFfile {} --soloCBwhitelist None {}".format(config["ref"]["annotation"], config["parameters"]["star"]["drop-seq"])
        return extra
    elif config["technology"] == "custom":
        extra = "--sjdbGTFfile {} --soloCBwhitelist None {}".format(config["ref"]["annotation"], config["parameters"]["star"]["custom"])
        return extra
    else:
        raise ValueError('Specified technology is not valid.')

rule star:
    input:
        #star needs the barcoding read (read 1) to be in the second position
        fq1=lambda wc: input_star(wc.sample,2),
        fq2=lambda wc: input_star(wc.sample,1),
        idx=config["ref"]["idx"]
    output:
        aln="{}/star/{{sample}}/Aligned.sortedByCoord.out.bam".format(OUTDIR),
        velo="{}/star/{{sample}}/Solo.out/Velocyto/Summary.csv".format(OUTDIR)
    log:
        f"{LOGDIR}/star/{{sample}}.log"
    benchmark:
        f"{LOGDIR}/star/{{sample}}.bmk"
    params:
        index=config["ref"]["idx"],
        extra=extra_params,
        prefix="{}/star/{{sample}}/".format(OUTDIR)
    threads: get_resource("star","threads")
    conda: "../envs/star.yaml"
    resources:
        mem_mb=get_resource("star","mem_mb"),
        walltime=get_resource("star","walltime")
    shell: 
        """
        STAR --runThreadN 8 --genomeDir {input.idx} --readFilesIn {input.fq1} {input.fq2} --readFilesCommand zcat --outFileNamePrefix {params.prefix} --outStd Log {params.extra}
        """
