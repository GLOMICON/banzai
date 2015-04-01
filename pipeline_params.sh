#!/bin/bash

# What is the path to the primer tags?
# This file should be simply a list of sequences, one per line, of each of the tags, WITH A TRAILING NEWLINE!
# To make a trailing newline, make sure when you open the file, you have hit enter after the final sequence.
PRIMER_TAGS=''

# How many nucleotides pad the 5' end of the tag sequence?
TAG_Ns=""
# What is the maximum number of Ns to allow at the end of a sequence before a tag is reached?
# TAG_N_MAX="9" # THIS IS NOT WORKING YET. SET TO DEFAULT 9



# What is the path to the reads?
READ1=''
READ2=''

# Is it ok to rename the sequences within a fasta file?
# This will happen after the fastq has been converted to a fasta file at the quality filtering step.
RENAME_READS="YES"

# What is the maximum expected length of the fragment of interest, including primers? # AND TAGS?
LENGTH_FRAG="180"

# What is the length of the reads of the Illumina run? (i.e. how long are the sequences in each of the run fastq files (R1 and R2)?)
# LENGTH_READ="150"

# Specify the path to the MEGAN executable file you want to use.
megan_exec='/Applications/megan/MEGAN'

################################################################################
# PRIMER REMOVAL
# Specify a path to the fasta file containing the two primers used to generate the amplicons you sequenced:
PRIMER_FILE=''

# What proportion of mismatches are you willing to accept when looking for primers?
PRIMER_MISMATCH_PROPORTION="0.10"

################################################################################
# HOMOPOLYMERS
# Would you like to remove reads containing runs of consecutive identical bases (homopolymers)?
REMOVE_HOMOPOLYMERS="NO"
# What is the maximum homopolymer length you're willing to accept?
# Reads containing runs of identical bases longer than this will be discarded.
HOMOPOLYMER_MAX="7"

################################################################################
# CLUSTERING:
# Would you like to cluster sequences into OTUs based on similarity?
CLUSTER_OTUS="YES"

# What percent similarity must sequences share to be considered the same OTU?
# Note that this must be an integer. Contact me if this is a problem
CLUSTERING_PERCENT="99"


################################################################################
# BLAST:
# Specify the path to the BLAST database.
# Note this should be a path to any one of three files WITHOUT their extension *.nhr, *.nin, or *.nsq
BLAST_DB='/Users/threeprime/Documents/Data/genbank/16S/16S_20141107/16S_20141107'
# BLAST PARAMETERS
PERCENT_IDENTITY="90"
WORD_SIZE="50"
EVALUE="1e-20"
# number of matches recorded in the alignment:
MAXIMUM_MATCHES="25"

# What is the lowest taxonomic rank at which MEGAN should group OTUs?
COLLAPSE_RANK1="Family"
MINIMUM_SUPPORT="1"
MINIMUM_COMPLEXITY="0"
TOP_PERCENT="3"
MINIMUM_SUPPORT_PERCENT="0"
MINIMUM_SCORE="140"
LCA_PERCENT="70"
MAX_EXPECTED="1e-25"

# Do you want to perform a secondary MEGAN analysis, collapsing at a different taxonomic level?
PERFORM_SECONDARY_MEGAN="YES"
COLLAPSE_RANK2="Genus"

# Would you like to delete extraneous intermediate files once the analysis is finished? YES/NO
PERFORM_CLEANUP="NO"


####################### WOULD YOU LIKE TO PICK UP FROM AN EXISTING FILE?
# If reanalyzing existing demultiplexed data, point this variable to the directory storing the individual tag folders.
EXISTING_DEMULTIPLEXED_DIR='/Users/threeprime/Documents/Data/IlluminaData/16S/20141020/Analysis_20141023_1328/demultiplexed'

# Should demultiplexed samples be concatenated for annotation as a single unit? (Each read can still be mapped back to samples)
CONCATENATE_SAMPLES="YES"

# Have the reads already been paired?
ALREADY_PEARED="NO"
# YES/NO
PEAR_OUTPUT='/Users/threeprime/Documents/Data/IlluminaData/12S/20140930/Analysis_20141030_2020/1_merged.assembled.fastq.gz'

# Have the merged reads been quality filtered?
ALREADY_FILTERED="NO" # YES/NO
FILTERED_OUTPUT='/Users/threeprime/Documents/Data/IlluminaData/12S/20140930/Analysis_20141030_2020/2_filtered_renamed.fasta'


# Is the parallel compression utility 'pigz' installed? (Get it here: http://zlib.net/pigz/)
PIGZ_INSTALLED="YES"

# If you want to receive a text message when the pipeline finishes, input your number here:
PHONE_NUMBER="4077443377"
