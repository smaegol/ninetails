# ninetails

**An R package for finding non-adenosine poly(A) residues in Oxford Nanopore direct RNA sequencing reads**

<img align="right" width="200" height="220" src="https://user-images.githubusercontent.com/68285258/168554098-a5a5dee9-2c8f-4351-86b4-e6420a5b8ced.png">

## Introduction
* It works on Oxford Nanopore direct RNA sequencing reads basecalled by Guppy software
* It requires tail delimitation data produced by Nanopolish software
* It allows both for the detection of non-adenosine residues within the poly(A) tails and visual inspection of  read signals

The software is still under development, so all suggestions to improving it are welcome. Please note that the code contained herein may change frequently, so use it with caution.

## Prerequisites


## Installation

Currently, **ninetails** is not available on CRAN/Bioconductor, so you need to install it using ```devtools```.



You can install ninetails using the command below in R/R-studio:

```r
install.packages("devtools")
devtools::install_github('LRB-IIMCB/ninetails')
library(ninetails)
```

## Usage

### Classification of reads using wrapper function

### Classification of reads using standalone functions

### Visual inspection of reads of interest

## Citation

Please cite **ninetails** as: Gumińska N et al., Direct detection of non-adenosine nucleotides within poly(A) tails – a new tool for the analysis of post-transcriptional mRNA tailing

Preprint is in the preparation.

## Future plans

## Maintainer

Any issues regarding the **ninetails** should be addressed to Natalia Gumińska (nguminska (at) iimcb.gov.pl).
