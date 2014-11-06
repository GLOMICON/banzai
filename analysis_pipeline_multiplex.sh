#!/bin/bash

# Pipeline for analysis of MULTIPLEXED Illumina data, a la Jimmy

# An attempt to cause the script to exit if any of the commands returns a non-zero status (i.e. FAILS).
# set -e

# This command specifies the path to the directory containing the script
SCRIPT_DIR="$(dirname "$0")"

# Read in the parameter files
source "$SCRIPT_DIR/pipeline_params.sh"
source "$SCRIPT_DIR/pear_params.sh"

# Get the directory containing the READ1 file and assign it to variable READ_DIR.
READ_DIR="${READ1%/*}"

# Define a variable called START_TIME
START_TIME=$(date +%Y%m%d_%H%M)

# And make a directory with that timestamp
mkdir "${READ_DIR}"/Analysis_"${START_TIME}"
ANALYSIS_DIR="${READ_DIR}"/Analysis_"${START_TIME}"

# Copy these files into that directory as a verifiable log you can refer back to.
cp "${SCRIPT_DIR}"/analysis_pipeline_multiplex.sh "${ANALYSIS_DIR}"/analysis_pipeline_used.txt
cp "${SCRIPT_DIR}"/pipeline_params.sh "${ANALYSIS_DIR}"/pipeline_parameters.txt
cp "${SCRIPT_DIR}"/pear_params.sh "${ANALYSIS_DIR}"/pear_parameters.txt

# Read in primers and their reverse complements.
PRIMER1=$( awk 'NR==2' "${PRIMER_FILE}" )
PRIMER2=$( awk 'NR==4' "${PRIMER_FILE}" )
# PRIMER1RC=$( seqtk seq -r "${PRIMER_FILE}" | awk 'NR==2' )
# PRIMER2RC=$( seqtk seq -r "${PRIMER_FILE}" | awk 'NR==4' )
PRIMER1RC=$( echo ${PRIMER1} | tr "[ABCDGHMNRSTUVWXYabcdghmnrstuvwxy]" "[TVGHCDKNYSAABWXRtvghcdknysaabwxr]" | rev )
PRIMER2RC=$( echo ${PRIMER2} | tr "[ABCDGHMNRSTUVWXYabcdghmnrstuvwxy]" "[TVGHCDKNYSAABWXRtvghcdknysaabwxr]" | rev )

# REMOVE THE FOLLOWING ONCE WE ALL HAVE CUTADAPT >1.7 UP AND RUNNING
# Take ambiguities out of primers. The sed command says "turn any character that's not A, T, C, or G, and replace it with N.
PRIMER1_NON=$( echo $PRIMER1 | sed "s/[^ATCG]/N/g" )
PRIMER2_NON=$( echo $PRIMER2 | sed "s/[^ATCG]/N/g" )
PRIMER1RC_NON=$( echo $PRIMER1RC | sed "s/[^ATCG]/N/g" )
PRIMER2RC_NON=$( echo $PRIMER2RC | sed "s/[^ATCG]/N/g" )

#MERGE PAIRED-END READS (PEAR)
if [ "$ALREADY_PAIRED" = "YES" ]; then
	MERGED_READS="$PEAR_OUTPUT"
else
	MERGED_READS_PREFIX="${ANALYSIS_DIR}"/1_merged
	MERGED_READS="${ANALYSIS_DIR}"/1_merged.assembled.fastq
	pear -f "${READ1}" -r "${READ2}" -o "${MERGED_READS_PREFIX}" -v $MINOVERLAP -m $ASSMAX -n $ASSMIN -t $TRIMMIN -q $QT -u $UNCALLEDMAX -g $TEST -p $PVALUE -s $SCORING -j $THREADS
fi

# FILTER READS (This is the last step that uses quality scores, so convert to fasta)
# The 32bit version of usearch will not accept an input file greater than 4GB. The 64bit usearch is $900. Thus, for now:
echo "Calculating merged file size..."
INFILE_SIZE=$(stat "${ANALYSIS_DIR}"/1_merged.assembled.fastq | awk '{ print $8 }')
if [ ${INFILE_SIZE} -gt 4000000000 ]; then
# Must first check the number of reads. If odd, file must be split so as not to split the middle read's sequence from its quality score.
	echo "Splitting large input file for quality filtering..."
	LINES_MERGED=$(wc -l < "${ANALYSIS_DIR}"/1_merged.assembled.fastq)
	READS_MERGED=$(( LINES_MERGED / 4 ))
	HALF_LINES=$((LINES_MERGED / 2))
	if [ $((READS_MERGED%2)) -eq 0 ]; then
		head -n ${HALF_LINES} "${ANALYSIS_DIR}"/1_merged.assembled.fastq > "${ANALYSIS_DIR}"/1_merged.assembled_A.fastq
		tail -n ${HALF_LINES} "${ANALYSIS_DIR}"/1_merged.assembled.fastq > "${ANALYSIS_DIR}"/1_merged.assembled_B.fastq
	else
		head -n $(( HALF_LINES + 2 )) "${ANALYSIS_DIR}"/1_merged.assembled.fastq > "${ANALYSIS_DIR}"/1_merged.assembled_A.fastq
		tail -n $(( HALF_LINES - 2 )) "${ANALYSIS_DIR}"/1_merged.assembled.fastq > "${ANALYSIS_DIR}"/1_merged.assembled_B.fastq
	fi
	usearch -fastq_filter "${ANALYSIS_DIR}"/1_merged.assembled_A.fastq -fastq_maxee 0.5 -fastq_minlen "${ASSMIN}" -fastaout "${ANALYSIS_DIR}"/2_filtered_A.fasta
	usearch -fastq_filter "${ANALYSIS_DIR}"/1_merged.assembled_B.fastq -fastq_maxee 0.5 -fastq_minlen "${ASSMIN}" -fastaout "${ANALYSIS_DIR}"/2_filtered_B.fasta
	cat "${ANALYSIS_DIR}"/2_filtered_A.fasta "${ANALYSIS_DIR}"/2_filtered_B.fasta > "${ANALYSIS_DIR}"/2_filtered.fasta
else
	usearch -fastq_filter "${ANALYSIS_DIR}"/1_merged.assembled.fastq -fastq_maxee 0.5 -fastq_minlen "${ASSMIN}" -fastaout "${ANALYSIS_DIR}"/2_filtered.fasta
fi

# REMOVE SEQUENCES CONTAINING HOMOPOLYMERS
if [ "${REMOVE_HOMOPOLYMERS}" = "YES" ]; then
	echo "Removing homopolymers..."
	grep -E -i "(A|T|C|G)\1{$HOMOPOLYMER_MAX,}" "${ANALYSIS_DIR}"/2_filtered.fasta -B 1 -n | cut -f1 -d: | cut -f1 -d- | sed '/^$/d' > "${ANALYSIS_DIR}"/homopolymer_line_numbers.txt
	if [ -s "${ANALYSIS_DIR}"/homopolymer_line_numbers.txt ]; then
		awk 'NR==FNR{l[$0];next;} !(FNR in l)' "${ANALYSIS_DIR}"/homopolymer_line_numbers.txt "${ANALYSIS_DIR}"/2_filtered.fasta > "${ANALYSIS_DIR}"/3_no_homopolymers.fasta
		awk 'NR==FNR{l[$0];next;} (FNR in l)' "${ANALYSIS_DIR}"/homopolymer_line_numbers.txt "${ANALYSIS_DIR}"/2_filtered.fasta > "${ANALYSIS_DIR}"/homopolymeric_reads.fasta
		DEMULTIPLEX_INPUT="${ANALYSIS_DIR}"/3_no_homopolymers.fasta
	else
		echo "No homopolymers found" > "${ANALYSIS_DIR}"/3_no_homopolymers.fasta
		DEMULTIPLEX_INPUT="${ANALYSIS_DIR}"/2_filtered.fasta
	fi
else
	echo "Homopolymers not removed."
	DEMULTIPLEX_INPUT="${ANALYSIS_DIR}"/2_filtered.fasta
fi

# DEMULTIPLEXING STARTS HERE
# make a directory to put all the demultiplexed files in
mkdir "${ANALYSIS_DIR}"/demultiplexed

N_TAGS=$( wc -l < "${PRIMER_TAGS}" )

# Write a file of sequence names to make a tag fasta file (necessary for reverse complementing)
# for i in `seq ${N_TAGS}`; do echo \>tag"$i"; done > "${ANALYSIS_DIR}"/tag_names.txt
# Alternately paste those names and the sequences to make a tag fasta file.
# paste -d"\n" "${ANALYSIS_DIR}"/tag_names.txt "${PRIMER_TAGS}" > "${ANALYSIS_DIR}"/tags.fasta
# Reverse complement the tags
# seqtk seq -r "${ANALYSIS_DIR}"/tags.fasta > "${ANALYSIS_DIR}"/tags_RC.fasta


# The old loop: Start the loop, do one loop for each of the number of lines in the tag file.
# for (( i=1; i<=${N_TAGS}; i++ ));

# PARALLEL DEMULTIPLEXING
# make tag sequences into a list
TAGS=$(tr '\n' ' ' < "${PRIMER_TAGS}" )

echo "Demultiplexing..."
# Move sequences into separate directories based on tag sequence on left side of read
for TAG_SEQ in $TAGS; do
(	TAG_DIR="${ANALYSIS_DIR}"/demultiplexed/tag_"${TAG_SEQ}"
	mkdir "${TAG_DIR}"
	awk '/^.{0,9}'"$TAG_SEQ"'/{if (a && a !~ /^.{0,9}'"$TAG_SEQ"'/) print a,"TAG_""'"$TAG_SEQ"'"; print} {a=$0}' "${DEMULTIPLEX_INPUT}" > "${TAG_DIR}"/1_tagL_present.fasta ) &
done

wait

# Remove tags from left side of read
for TAG_SEQ in $TAGS; do
(	TAG_DIR="${ANALYSIS_DIR}"/demultiplexed/tag_"${TAG_SEQ}"
	sed -E 's/^.{0,9}'"${TAG_SEQ}"'//' "${TAG_DIR}"/1_tagL_present.fasta > "${TAG_DIR}"/2_tagL_removed.fasta ) &
done

wait

# Identify reads containing tags towards the right side of the read
for TAG_SEQ in $TAGS; do
(	TAG_DIR="${ANALYSIS_DIR}"/demultiplexed/tag_"${TAG_SEQ}"
	TAG_RC=$( echo ${TAG_SEQ} | tr "[ATGCatgcNn]" "[TACGtacgNn]" | rev )
	grep -E "${TAG_RC}.{0,9}$" -B 1 "${TAG_DIR}"/2_tagL_removed.fasta | grep -v -- "^--$"  > "${TAG_DIR}"/3_tagR_present.fasta ) &
done

wait

for TAG_SEQ in $TAGS; do
(	TAG_DIR="${ANALYSIS_DIR}"/demultiplexed/tag_"${TAG_SEQ}"
	TAG_RC=$( echo ${TAG_SEQ} | tr "[ATGCatgcNn]" "[TACGtacgNn]" | rev )
	sed -E 's/'"${TAG_RC}"'.{0,9}$//' "${TAG_DIR}"/3_tagR_present.fasta > "${TAG_DIR}"/4_tagR_removed.fasta ) &
done

wait

# Assign the current tag to to variable TAG, and its reverse complement to TAG_RC
# TAG=$( sed -n $((i * 2))p "${ANALYSIS_DIR}"/tags.fasta )
# TAG_RC=$( sed -n $((i * 2))p "${ANALYSIS_DIR}"/tags_RC.fasta )

# Create a directory for the tag
# mkdir "${ANALYSIS_DIR}"/demultiplexed/tag_"${i}"

# Make a variable (CURRENT_DIR) with the current tag's directory for ease of reading and writing.
# CURRENT_DIR="${ANALYSIS_DIR}"/demultiplexed/tag_"${i}"

# REMOVE TAG SEQUENCES
# remove the tag from the beginning of the sequence (5' end) in it's current orientation
# cutadapt -g ^NNN"${TAG}" -e 0 --discard-untrimmed "${DEMULTIPLEX_INPUT}" > "${CURRENT_DIR}"/5prime_tag_rm.fasta

# Need to first grep lines containing pattern first, THEN following sed command with remove them
# grep -E "${TAG_RC}.{0,9}$" -B 1 "${CURRENT_DIR}"/5prime_tag_rm.fasta | grep -v -- "^--$"  > "${CURRENT_DIR}"/3_prime_tagged.fasta
# Turn the following line on to write chimaeras to a file.
# grep -E -v "${TAG_RC}.{0,9}$" "${CURRENT_DIR}"/5prime_tag_rm.fasta > "${CURRENT_DIR}"/chimaeras.fasta
# This sed command looks really f***ing ugly; but I'm pretty sure it works.
# sed -E 's/'"${TAG_RC}"'.{0,9}$//' "${CURRENT_DIR}"/3_prime_tagged.fasta > "${CURRENT_DIR}"/3prime_tag_rm.fasta

# The following are already parallelized; thus keep everything wrapped in one loop
for TAG_SEQ in $TAGS; do

TAG_DIR="${ANALYSIS_DIR}"/demultiplexed/tag_"${TAG_SEQ}"

# REMOVE PRIMER SEQUENCES
# Remove PRIMER1 and PRIMER2 from the beginning of the reads. NOTE cutadapt1.7+ will accept ambiguities in primers.
cutadapt -g ^"${PRIMER1_NON}" -g ^"${PRIMER2_NON}" -e "${PRIMER_MISMATCH_PROPORTION}" --discard-untrimmed "${TAG_DIR}"/4_tagR_removed.fasta > "${TAG_DIR}"/5_primerL_removed.fasta
# Remove the reverse complement of PRIMER1 and PRIMER2 from the end of the reads. NOTE cutadapt1.7 will account for anchoring these to the end of the read with $
cutadapt -a "${PRIMER1RC_NON}" -a "${PRIMER2RC_NON}" -e "${PRIMER_MISMATCH_PROPORTION}" --discard-untrimmed "${TAG_DIR}"/5_primerL_removed.fasta > "${TAG_DIR}"/6_primerR_removed.fasta

DEREP_INPUT="${TAG_DIR}"/6_primerR_removed.fasta

# CONSOLIDATE IDENTICAL SEQUENCES.
usearch -derep_fulllength "${DEREP_INPUT}" -sizeout -strand both -uc "${TAG_DIR}"/derep.uc -output "${TAG_DIR}"/7_derep.fasta

# REMOVE SINGLETONS
usearch -sortbysize "${TAG_DIR}"/7_derep.fasta -minsize 2 -sizein -sizeout -output "${TAG_DIR}"/8_nosingle.fasta

# CLUSTER SEQUENCES
if [ "$BLAST_WITHOUT_CLUSTERING" = "YES" ]; then
	BLAST_INPUT="${TAG_DIR}"/8_nosingle.fasta
else
	CLUSTER_RADIUS="$(( 100 - ${CLUSTERING_PERCENT} ))"
	usearch -cluster_otus "${TAG_DIR}"/8_nosingle.fasta -otu_radius_pct "${CLUSTER_RADIUS}" -sizein -sizeout -otus "${TAG_DIR}"/9_OTUs.fasta -notmatched "${TAG_DIR}"/9_notmatched.fasta
	BLAST_INPUT="${TAG_DIR}"/9_OTUs.fasta
fi

# BLAST CLUSTERS
blastn -query "${BLAST_INPUT}" -db "$BLAST_DB" -perc_identity "${PERCENT_IDENTITY}" -word_size "${WORD_SIZE}" -evalue "${EVALUE}" -max_target_seqs "${MAXIMUM_MATCHES}" -outfmt 5 -out "${TAG_DIR}"/10_BLASTed.xml

# Some POTENTIAL OPTIONS FOR MEGAN EXPORT:
# {readname_taxonname|readname_taxonid|readname_taxonpath|readname_matches|taxonname_count|taxonpath_count|taxonid_count|taxonname_readname|taxonpath_readname|taxonid_readname}
# PERFORM COMMON ANCESTOR GROUPING IN MEGAN
cat > "${TAG_DIR}"/megan_commands.txt <<EOF
import blastfile='${TAG_DIR}/10_BLASTed.xml' meganfile='${TAG_DIR}/meganfile.rma' [minSupport=${MINIMUM_SUPPORT}] [minComplexity=${MINIMUM_COMPLEXITY}] [topPercent=${TOP_PERCENT}] [minSupportPercent=${MINIMUM_SUPPORT_PERCENT}] [minScore=${MINIMUM_SCORE}];
update;
collapse rank='$COLLAPSE_RANK';
update;
select nodes=all;
export what=DSV format=readname_taxonname separator=comma file=${TAG_DIR}/meganout.csv;
quit;
EOF

cat > "${TAG_DIR}"/megan_script.sh <<EOF
#!/bin/bash
cd "${megan_exec%/*}"
./"${megan_exec##*/}" -g -E -c ${TAG_DIR}/megan_commands.txt
EOF

sh "${TAG_DIR}"/megan_script.sh

# Modify the MEGAN output so that it is a standard CSV file with cluterID, N_reads, and Taxon
sed 's|;size=|,|' <"${TAG_DIR}"/meganout.csv >"${TAG_DIR}"/meganout_mod.csv

# Copy the plotting script to the current directory
cp "${SCRIPT_DIR}"/megan_plotter.R "${TAG_DIR}"/megan_plotter.R

# PLOTTING ANNOTATIONS
# Add a line (before line 4) to change R's directory to the one the loop is working in (the variable ${CURRENT_DIR}), and copy to the current directory
sed "4i\\
setwd('"${TAG_DIR}"')
" ${SCRIPT_DIR}/megan_plotter.R > ${TAG_DIR}/megan_plotter.R

Rscript "${TAG_DIR}"/megan_plotter.R

done

if [ "$PERFORM_CLEANUP" = "YES" ]; then
	echo "Compressing fasta and fastq files..."
	find "${ANALYSIS_DIR}" -type f -name '*.fasta' -exec gzip "{}" \;
	find "${ANALYSIS_DIR}" -type f -name '*.fastq' -exec gzip "{}" \;
	echo "Cleanup performed."
else
	echo "Cleanup not performed."
fi
