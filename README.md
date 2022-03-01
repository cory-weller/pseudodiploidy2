# Yeast Pseudodiploidy

## Singularity
### Install Singularity
```
bash src/install-singularity.sh
```

### Build Singularity image
```
singularity build --fakeroot src/pseudodiploidy.sif src/pseudodiploidy.def
```


## Retrieve data
```
bash src/get-data.sh
```

## Transform data
```
# Build count matrix for DESeq
singularity exec --bind ${PWD} src/R.sif Rscript \
    src/build-count-matrix.R \
    data/input/combined-featurecounts.csv \
    data/input/samples.csv \
    data/processed/featurecounts-matrix.RDS

# Build TPM table for other analyses
singularity exec --bind ${PWD} src/R.sif Rscript \
    src/build-TPM-table.R \
    data/input/combined-featurecounts.csv \
    data/input/samples.csv \
    data/processed/TPM.txt.gz

# Build DESeq Data Set (DDS) Object
singularity exec --bind ${PWD} src/R.sif Rscript \
    src/build-DDS.R \
    data/processed/featurecounts-matrix.RDS \
    data/input/samples.csv \
    data/processed/DDS.RDS

# Run differential expression contrasts
singularity exec --bind ${PWD} src/R.sif Rscript \
    src/run-contrast.R
```

# Run exploratory analyses
```
singularity exec --bind ${PWD} src/R.sif R
```
