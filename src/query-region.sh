#!/usr/bin/env bash

chromosome=${1}
start=${2}
stop=${3}
replicates=${4}

singularity exec --bind $PWD src/pseudodiploidy.sif Rscript src/query-region.R ${chromosome} ${start} ${stop} ${replicates}
