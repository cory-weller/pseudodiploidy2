import pandas as pd
samples = pd.read_table("samples.tsv").set_index("sample", drop=False)
configfile: "config.yaml"

project_path = config['project_path']


SAMPLES = list(samples['sample'])   # SAMPLES: list of samples of given BATCH that will be processed
BATCH = config['run']['batch']      # BATCH: identifies the group of samples we're concerned with, e.g. date of sequencing run
GENES = list(config['amplicons'].keys())

def wrap_fasta(seq, line_length=80):
    return '\n'.join([seq[i:i+line_length] for i in range(0, len(seq), line_length)])

# rule targets identifies the list of final output files to generate
rule targets:
    """Defines the set of files desired at end of pipeline"""
    input:
        expand("data/processed/{batch}-{sample}-{gene}.counts", batch=BATCH, sample=SAMPLES, gene=GENES + ['nomatch'])
        #expand("data/processed/{batch}-{sample}-{gene}.fa", batch=BATCH, sample=SAMPLES, gene=GENES)
        #expand("data/processed/{batch}-{sample}-summary.txt", batch=BATCH, sample=SAMPLES)
        #expand("data/processed/{batch}-{sample}-{gene}.txt", batch=BATCH, sample=SAMPLES, gene=GENES)
        #expand("data/input/{batch}-{sample}.assembled.fastq", batch=BATCH, sample=SAMPLES)

rule make_fastas:
    output: expand("data/input/{gene}-wt.fasta", gene=GENES)
    threads: 1
    resources:
        mem_mb = 1024*1,
        runtime_min = 5,
    run:
        for gene in GENES:
            seq = ''.join([config['amplicons'][gene][i] for i in ['upstream','wt','downstream']])
            seq_wrapped = wrap_fasta(seq)
            header = f">{gene}\n"
            outfile = f"data/input/{gene}-wt.fasta"
            print(f"seq:{seq_wrapped}\nheader:{header}\noutfile:{outfile}")
            with open(outfile, 'w', encoding='utf-8') as o:
                print(header + seq_wrapped, file=o)


rule get_reads:
    """Downloads reads from storage specified in samples.tsv"""
    output: 
        "data/input/{batch}-{sample}-R1-{stage}.fastq.gz",
        "data/input/{batch}-{sample}-R2-{stage}.fastq.gz"
    threads: 1
    resources:
        mem_mb = 1024*1,
        runtime_min = 5,
    params:
        filename1 = lambda wc: samples.loc[wc.sample, 'filename1'],
        filename2 = lambda wc: samples.loc[wc.sample, 'filename2'],
        ida = lambda wc: samples.loc[wc.sample, 'ida'],
        idb1 = lambda wc: samples.loc[wc.sample, 'idb1'],
        idc1 = lambda wc: samples.loc[wc.sample, 'idc1'],
        idb2 = lambda wc: samples.loc[wc.sample, 'idb2'],
        idc2 = lambda wc: samples.loc[wc.sample, 'idc2']
    shell:
        """
        wget -O data/input/{params.filename1} https://onedrive.live.com/download?cid={params.ida}\\&resid={params.ida}%{params.idb1}\&authkey={params.idc1}
        wget -O data/input/{params.filename2} https://onedrive.live.com/download?cid={params.ida}\\&resid={params.ida}%{params.idb2}\&authkey={params.idc2}
        """

rule pair_with_pear:
    """Assembles forward and reverse read pair into single overlapping read"""
    input:
        r1="data/input/{batch}-{sample}-R1-raw.fastq.gz",
        r2="data/input/{batch}-{sample}-R2-raw.fastq.gz"
    output: 
        "data/input/{batch}-{sample}.assembled.fastq",
        temp("data/input/{batch}-{sample}.unassembled.forward.fastq"),
        temp("data/input/{batch}-{sample}.unassembled.reverse.fastq"),
        temp("data/input/{batch}-{sample}.discarded.fastq")
    threads: 2
    resources:
        mem_mb = 1024*4,
        runtime_min = 60*2,
    container: "library://wellerca/pseudodiploidy/mapping:latest"
    shell:
        """
        pear -f {input.r1} -r {input.r2} -o data/input/{wildcards.batch}-{wildcards.sample}
        rm data/input/{wildcards.batch}-{wildcards.sample}.unassembled.{{forward,reverse}}.fastq
        rm data/input/{wildcards.batch}-{wildcards.sample}.discarded.fastq
        """

rule get_read_set_counts:
    """Converts a fastq file to table of <count> <read>"""
    input: "data/input/{batch}-{sample}.assembled.fastq"
    output: "data/processed/{batch}-{sample}.assembled.fastq.counts"
    threads: 1
    resources:
        mem_mb = 1024*4,
        runtime_min = 10,
    shell:
        """
        bash src/get_read_set_counts {input} > {output}
        """

rule assess_reads:
    input: 
        "data/processed/{batch}-{sample}.assembled.fastq.counts"
    output:
        expand("data/processed/{{batch}}-{{sample}}-{gene}.counts", gene=GENES + ['nomatch'])
    threads: 1
    resources:
        mem_mb = 1024*4,
        runtime_min = 60,
    shell:
        """
        python src/analyze_sim_reads.py {input}
        """

rule convert_to_fasta:
    input:
        "data/processed/{batch}-{sample}-{gene}.counts"
    output:
        "data/processed/{batch}-{sample}-{gene}.fa"
    threads: 1
    resources:
        mem_mb = 1024*2,
        runtime_min = 10,
    shell:
        """
        bash src/convert_to_fasta.sh {input} > {output}
        """

rule align:
    input:
        seqs="data/processed/{batch}-{sample}-{gene}.fa",
        wt="data/input/{gene}-wt.fasta"
    output:
        "data/processed/{batch}-{sample}-{gene}.aln"
    threads: 1
    resources:
        mem_mb = 1024*4,
        runtime_min = 180,
    shell:
        """
        # If input sequence file is not empty
        if [ -s {input.seqs} ]; then                                    
            cat {input.wt} {input.seqs} | src/clustalo -i - -o {output}
        else;
            echo {input.seqs} is empty! Nothing to align
            touch {output}
        fi
        """
