#!/usr/bin/env bash

# Pipeline for analysis of MULTIPLEXED Illumina data, a la Jimmy

echo
echo
echo -e '\t' "\x20\xf0\x9f\x8f\x84" " "  "\xc2\xa1" BANZAI !
echo
echo


################################################################################
# CHECK FOR RAW DATA
################################################################################

# Define a variable called START_TIME
START_TIME=$(date +%Y%m%d_%H%M)
START_TIME_SEC=$(date +%Y%m%d_%H%M%S)

# Find the directory this script lives in, so it can find its friends.
SCRIPT_DIR="$(dirname "$0")"

# Read in the parameter file (was source "$SCRIPT_DIR/banzai_params.sh"; now argument 1)
param_file="${1}"
source "${param_file}"

# check if param file exists:
if [[ -s "${param_file}" ]] ; then
	echo "Reading analysis parameters from:"
	echo "${param_file}"
	echo
else
	echo
	echo 'ERROR! Could not find analysis parameter file. You specified the file path:'
	echo
	echo "${param_file}"
	echo
	echo 'That file is empty or does not exist. Aborting script.'
	exit
fi


# check if sequencing metadata exists
if [[ -s "${SEQUENCING_METADATA}" ]] ; then
	echo "Reading sequencing metadata from:"
	echo "${SEQUENCING_METADATA}"
	echo
else
	echo
	echo 'ERROR! Could not find sequencing metadata file. You specified the file path:'
	echo
	echo "${SEQUENCING_METADATA}"
	echo
	echo 'That file is empty or does not exist. Aborting script.'
	exit
fi

# check for correct newline characters (CRLF will break things)
source "${SCRIPT_DIR}"/scripts/newline_fix.sh "${SEQUENCING_METADATA}"
if [[ -s "${NEWLINES_FIXED}" ]]; then
	SEQUENCING_METADATA="${NEWLINES_FIXED}"
fi

################################################################################
# CHECK FOR DEPENDENCIES
################################################################################
dependencies=($( echo pear cutadapt vsearch swarm seqtk python blastn R ))
source "${SCRIPT_DIR}"/scripts/dependency_check.sh "${dependencies[@]}"


# Specify compression utility
if hash pigz 2>/dev/null; then
	ZIPPER="pigz"
	echo "pigz installation found"
	echo
else
	ZIPPER="gzip"
	echo "pigz installation not found; using gzip"
	echo
fi

# Detect number of cores on machine; set variable
n_cores=$(getconf _NPROCESSORS_ONLN)
if [ $n_cores -gt 1 ]; then
	echo "$n_cores cores detected."
	echo
else
	n_cores=1
	echo "Multiple cores not detected."
	echo
fi

# make an analysis directory with starting time timestamp
OUTPUT_DIR="${OUTPUT_DIRECTORY}"/banzai_out_"${START_TIME}"
if [[ -d "${OUTPUT_DIR}" ]]; then
	OUTPUT_DIR="${OUTPUT_DIRECTORY}"/banzai_out_"${START_TIME_SEC}"
	if [[ -d "${OUTPUT_DIR}" ]]; then
		echo "Output directory already exists!"
		echo "${OUTPUT_DIR}"
		echo "Aborting script."
		exit
	fi
fi
mkdir "${OUTPUT_DIR}"

# Write a log file of output from this script (everything that prints to terminal)
LOGFILE="${OUTPUT_DIR}"/logfile.txt
exec > >(tee "${LOGFILE}") 2>&1

echo $(date +%Y-%m-%d\ %H:%M) "Analysis started at ""${START_TIME}"
echo "Output is located in:"
echo "${OUTPUT_DIR}"
echo

# Copy these files into that directory as a verifiable log you can refer back to.
cp "${SCRIPT_DIR}"/banzai.sh "${OUTPUT_DIR}"/analysis_script.txt
cp "${param_file}" "${OUTPUT_DIR}"/analysis_parameters.txt



################################################################################
# READ FILE NAMES
################################################################################
FILE1_COLNUM=$(awk -F',' -v FILE1_COL=$FILE1_COLNAME \
  '{for (i=1;i<=NF;i++)
	    if($i == FILE1_COL)
		  print i;
		exit}' \
$SEQUENCING_METADATA)

FILE2_COLNUM=$(awk -F',' -v FILE2_COL=$FILE2_COLNAME \
	'{for (i=1;i<=NF;i++)
	    if($i == FILE2_COL)
			print i;
		exit}' \
$SEQUENCING_METADATA)

FILE1=($(awk -F',' -v FILE1_COL=$FILE1_COLNUM \
	'NR>1 {print $FILE1_COL}' \
$SEQUENCING_METADATA |\
sort | uniq ))

FILE2=($(awk -F',' -v FILE2_COL=$FILE2_COLNUM \
	'NR>1 {print $FILE2_COL}' \
$SEQUENCING_METADATA |\
sort | uniq ))

NFILE1="${#FILE1[@]}"
NFILE2="${#FILE2[@]}"
if [ "${NFILE1}" != "${NFILE2}" ]; then
	echo "ERROR: Whoa! different number of forward and reverse files"
fi

if [[ -n "${FILE1}" && -n "${FILE2}" ]]; then
  echo 'Files read from metadata columns' "${FILE1_COLNUM}" 'and' "${FILE2_COLNUM}"
  echo 'File names:'
	for (( i=0; i < "${NFILE1}"; ++i)); do
		printf '%s\t%s\n' "${FILE1[i]}" "${FILE2[i]}"
	done
	echo
else
  echo 'ERROR:' 'At least one file is not valid'
  echo 'Looked in metadata columns' "${FILE1_COLNUM}" 'and' "${FILE2_COLNUM}"
  echo 'Aborting script'
  exit
fi

################################################################################
# LOAD MULTIPLEX INDEXES
################################################################################
IND2_COL=$(awk -F',' -v IND2_COLNAME=$SECONDARY_INDEX_COLUMN_NAME '{
	for (i=1;i<=NF;i++)
	  if($i == IND2_COLNAME)
			print i;
	exit
}' $SEQUENCING_METADATA)
IND2S=$(awk -F',' -v INDCOL=$IND2_COL \
'NR>1 {
	print $INDCOL
}' $SEQUENCING_METADATA |\
sort | uniq)
N_index_sequences=$(echo $IND2S | awk '{print NF}')

# check if number of tags is greater than one:
if [[ "${N_index_sequences}" -gt 1 ]]; then
	echo "Multiplex tags read from sequencing metadata (""${N_index_sequences}"" total)"
	echo
else
  echo
  echo 'ERROR:' "${N_index_sequences}" 'index sequences found. There should probably be more than 1.'
  echo
  echo 'Aborting script.'
	exit
fi

declare -a IND2_ARRAY=($IND2S)


################################################################################
# Read in primers and create reverse complements.
################################################################################
PRIMER1_COLNUM=$(awk -F',' -v PRIMER1_COL=$PRIMER_1_COLUMN_NAME '{
	for (i=1;i<=NF;i++)
	  if($i == PRIMER1_COL)
		  print i;
		exit
}' $SEQUENCING_METADATA)

PRIMER2_COLNUM=$(awk -F',' -v PRIMER2_COL=$PRIMER_2_COLUMN_NAME '{
	for (i=1;i<=NF;i++)
	  if($i == PRIMER2_COL)
		  print i;
	exit
}' $SEQUENCING_METADATA)

PRIMER1=$(awk -F',' -v PRIMER1_COL=$PRIMER1_COLNUM \
'NR==2 {
	print $PRIMER1_COL
}' $SEQUENCING_METADATA)

PRIMER2=$(awk -F',' -v PRIMER2_COL=$PRIMER2_COLNUM \
'NR==2 {
	print $PRIMER2_COL
}' $SEQUENCING_METADATA)

if [[ -n "${PRIMER1}" && -n "${PRIMER2}" ]]; then
  echo 'Primers read from metadata columns' "${PRIMER1_COLNUM}" 'and' "${PRIMER2_COLNUM}"
  echo 'Primer sequences:' "${PRIMER1}" "${PRIMER2}"
	echo
else
  echo 'ERROR:' 'At least one primer is not valid'
  echo 'Looked in metadata columns' "${PRIMER1_COLNUM}" 'and' "${PRIMER2_COLNUM}"
  echo 'Aborting script'
  exit
fi

# make primer array
read -a primers_arr <<< $( echo $PRIMER1 $PRIMER2 )

# Reverse complement primers
source "${SCRIPT_DIR}"/misc/revcom.sh
PRIMER1RC=$( revcom "${PRIMER1}" )
PRIMER2RC=$( revcom "${PRIMER2}" )

# make primer array
read -a primersRC_arr <<< $( echo $PRIMER1RC $PRIMER2RC )


################################################################################
# Calculate the expected size of the region of interest, given the total size of fragments, and the length of primers and tags
################################################################################
EXTRA_SEQ=${IND2_ARRAY[0]}${IND2_ARRAY[0]}$PRIMER1$PRIMER2
LENGTH_ROI=$(( $LENGTH_FRAG - ${#EXTRA_SEQ} ))
LENGTH_ROI_HALF=$(( $LENGTH_ROI / 2 ))


################################################################################
# Find raw sequence files
################################################################################
# Look for any file with '.fastq' in the name in the parent directory
# note that this will include ANY file with fastq -- including QC reports!
ID1_NAMES=($( find "$PARENT_DIR" -name '*.fastq*' -print0 | xargs -0 -n1 dirname | sort --unique ))

# PEAR v0.9.6 does not correctly merge .gz files.
# Look through files and decompress if necessary.
raw_files=($( find "${PARENT_DIR}" -name '*.fastq*' ))
for myfile in "${raw_files[@]}"; do
	if [[ "${myfile}" =~ \.gz$ ]]; then
		echo $(date +%Y-%m-%d\ %H:%M) "decompressing "${myfile}""
		"${ZIPPER}" -d "${myfile}"
	fi
done

# Count library directories and print the number found
N_library_dir="${#ID1_NAMES[@]}"
echo "${N_library_dir}"" library directories found:"

# Show the libraries that were found:
for i in "${ID1_NAMES[@]}"; do echo "${i##*/}" ; done
echo

# Assign it to a variable for comparison
LIBS_FROM_DIRECTORIES=$(for i in "${ID1_NAMES[@]}"; do echo "${i##*/}" ; done)

# Read library names from file or sequencing metadata
if [ "${READ_LIB_FROM_SEQUENCING_METADATA}" = "YES" ]; then

	COL_NUM_ID1=$(awk -F',' -v COL_NAME_ID1=$LIBRARY_COLUMN_NAME '{
		for (i=1;i<=NF;i++)
		  if($i == COL_NAME_ID1)
			  print i;
		exit
	}' $SEQUENCING_METADATA)

	ID1S=$(awk -F',' -v COLNUM_ID1=$COL_NUM_ID1 'NR>1 {
		print $COLNUM_ID1
	}' $SEQUENCING_METADATA | sort | uniq)

	N_libs=$(echo $ID1S | awk '{print NF}')

	echo "Library names read from sequencing metadata (""${N_libs}"") total"
	echo "${ID1S}"
	echo
else
	ID1S=$(tr '\n' ' ' < "${LIB_FILE}" )
	N_libs=$(echo $ID1S | awk '{print NF}')
	echo "Library names read from lib file (""${ID1S}"") total"
	echo
fi

# Check that library names are the same in the metadata and file system
if [ "$LIBS_FROM_DIRECTORIES" != "$ID1S" ]; then
	echo "Warning: Library directories and library names in metadata are NOT the same. Something will probably go wrong later..."
	echo
else
	echo "Library directories and library names in metadata are the same - great jorb."
	echo
fi


# Unique samples are given by combining the library and tags
# TODO originally contained sort | uniq; this is unnecessary I think
ID_COMBO=$( awk -F',' -v COLNUM_ID1=$COL_NUM_ID1 -v INDCOL=$IND2_COL \
'NR>1 {
  print "ID1_" $COLNUM_ID1 "_ID2_" $INDCOL
}' $SEQUENCING_METADATA | sort | uniq )

# create a file to store tag efficiency data
INDEX_COUNT="${OUTPUT_DIR}"/index_count.txt
echo "library tag left_tagged right_tagged" >> "${INDEX_COUNT}"

################################################################################
# BEGIN LOOP TO PERFORM LIBRARY-LEVEL ACTIONS
################################################################################

for CURRENT_ID1_NAME in "${ID1_NAMES[@]}"; do

	# Identify the forward and reverse fastq files.
	READS=($(find "${CURRENT_ID1_NAME}" -name '*.fastq*'))
	READ1="${READS[0]}"
	READ2="${READS[1]}"

	ID1_OUTPUT_DIR="${OUTPUT_DIR}"/${CURRENT_ID1_NAME##*/}
	mkdir "${ID1_OUTPUT_DIR}"

	##############################################################################
	# MERGE PAIRED-END READS AND QUALITY FILTER (PEAR)
	##############################################################################

	LENGTH_READ=$( head -n 100000 "${READ1}" | awk '{print length($0);}' |\
	  sort -nr | uniq | head -n 1 )

	if [ "${calculate_merge_length}" = "YES" ]; then
		##############################################################################
		# CALCULATE EXPECTED AND MINIMUM OVERLAP OF PAIRED END SEQUENCES
		##############################################################################
		OVERLAP_EXPECTED=$(($LENGTH_FRAG - (2 * ($LENGTH_FRAG - $LENGTH_READ) ) ))
		MINOVERLAP=$(( $OVERLAP_EXPECTED / 2 ))
		##############################################################################
		# CALCULATE MAXIMUM AND MINIMUM LENGTH OF MERGED READS
		##############################################################################
		ASSMAX=$(( $LENGTH_FRAG + 50 ))
		ASSMIN=$(( $LENGTH_FRAG - 50 ))
	else
		MINOVERLAP="${minimum_overlap}"
		ASSMAX="${assembled_max}"
		ASSMIN="${assembled_min}"
	fi

	if [ "$ALREADY_PEARED" = "YES" ]; then
		MERGED_READS="$PEAR_OUTPUT"
		echo "Paired reads have already been merged."
		echo
	else
		echo $(date +%Y-%m-%d\ %H:%M) "Merging reads in library" "${CURRENT_ID1_NAME##*/}""..."
		MERGED_READS_PREFIX="${ID1_OUTPUT_DIR}"/1_merged
		MERGED_READS="${ID1_OUTPUT_DIR}"/1_merged.assembled.fastq
		pear \
			--forward-fastq "${READ1}" \
			--reverse-fastq "${READ2}" \
			--output "${MERGED_READS_PREFIX}" \
			-v $MINOVERLAP \
			-m $ASSMAX \
			-n $ASSMIN \
			-t $min_seq_length \
			-q $Quality_Threshold \
			-u $UNCALLEDMAX \
			-g $TEST \
			-p $PVALUE \
			-s $SCORING \
			-j $n_cores

		# check pear output:
		if [[ ! -s "${MERGED_READS}" ]] ; then
		    echo 'ERROR: No reads were merged.'
		    echo 'Aborting analysis of this library, but will move on to next one.'
				continue
		fi

		echo


	fi
	# if [ "${HOARD}" = "NO" ]; then
	# fi

	################################################################################
	# EXPECTED ERROR FILTERING (vsearch)
	################################################################################
	# FILTER READS (This is the last step that uses quality scores, so convert to fasta)
	if [ "${Perform_Expected_Error_Filter}" = "YES" ]; then
		echo $(date +%Y-%m-%d\ %H:%M) "Filtering merged reads..."
		FILTERED_OUTPUT="${ID1_OUTPUT_DIR}"/2_filtered.fasta
		vsearch \
			--fastq_filter "${MERGED_READS}" \
			--fastq_maxee "${Max_Expected_Errors}" \
			--fastaout "${FILTERED_OUTPUT}" \
			--fasta_width 0

    echo
	else
		# Convert merged reads fastq to fasta
		echo  $(date +%Y-%m-%d\ %H:%M) "converting fastq to fasta..."
		FILTERED_OUTPUT="${MERGED_READS%.*}".fasta
		seqtk seq -A "${MERGED_READS}" > "${FILTERED_OUTPUT}"
		echo
	fi

	# Compress merged reads
  echo $(date +%Y-%m-%d\ %H:%M) "Compressing PEAR output..."
  find "${ID1_OUTPUT_DIR}" -type f -name '*.fastq' -exec ${ZIPPER} "{}" \;
  echo $(date +%Y-%m-%d\ %H:%M) "PEAR output compressed."
	echo


	if [ "${RENAME_READS}" = "YES" ]; then
		echo $(date +%Y-%m-%d\ %H:%M) "Renaming reads in library" "${CURRENT_ID1_NAME##*/}""..."
		# TODO remove whitespace from sequence labels?
		# sed 's/ /_/'

		# updated 20150521; one step solution using awk; removes anything after the first space!
		FILTERED_RENAMED="${FILTERED_OUTPUT%.*}"_renamed.fasta
		awk -F'[: ]' '{
				if ( /^>/ )
					print ">"$4":"$5":"$6":"$7"_ID1_'${CURRENT_ID1_NAME##*/}'_";
				else
					print $0
		}' "${FILTERED_OUTPUT}" > "${FILTERED_RENAMED}"

		mv "${FILTERED_RENAMED}" "${FILTERED_OUTPUT}"
		rm "${FILTERED_RENAMED}"

		echo $(date +%Y-%m-%d\ %H:%M) "Reads renamed"
		echo

	else

		awk '{
				if ( /^>/ )
					print "$0"_ID1_'${CURRENT_ID1_NAME##*/}'_";
				else
					print $0
		}' "${FILTERED_OUTPUT}" > "${FILTERED_RENAMED}"

		mv "${FILTERED_RENAMED}" "${FILTERED_OUTPUT}"
		rm "${FILTERED_RENAMED}"

		echo "Reads not renamed"
		echo

	fi


	################################################################################
	# HOMOPOLYMERS (grep, awk)
	################################################################################
	if [ "${REMOVE_HOMOPOLYMERS}" = "YES" ]; then
		echo $(date +%Y-%m-%d\ %H:%M) "Removing homopolymers..."
		HomoLineNo="${CURRENT_ID1_NAME}"/homopolymer_line_numbers.txt
		grep -E -i -B 1 -n "(A|T|C|G)\1{$HOMOPOLYMER_MAX,}" "${FILTERED_OUTPUT}" | \
			cut -f1 -d: | \
			cut -f1 -d- | \
			sed '/^$/d' > "${HomoLineNo}"
			echo
		if [ -s "${HomoLineNo}" ]; then
			DEMULTIPLEX_INPUT="${CURRENT_ID1_NAME}"/3_no_homopolymers.fasta
			awk 'NR==FNR{l[$0];next;} !(FNR in l)' "${HomoLineNo}" "${FILTERED_OUTPUT}" > "${DEMULTIPLEX_INPUT}"
			awk 'NR==FNR{l[$0];next;} (FNR in l)' "${HomoLineNo}" "${FILTERED_OUTPUT}" > "${CURRENT_ID1_NAME}"/homopolymeric_reads.fasta
		else
			echo "No homopolymers found" > "${CURRENT_ID1_NAME}"/3_no_homopolymers.fasta
			DEMULTIPLEX_INPUT="${FILTERED_OUTPUT}"
			echo
		fi
	else
		echo "Homopolymers not removed."
		DEMULTIPLEX_INPUT="${FILTERED_OUTPUT}"
		echo
	fi

	################################################################################
	# DEMULTIPLEXING (awk)
	################################################################################
  source "${SCRIPT_DIR}"/scripts/demultiplexing.sh
	echo

done

################################################################################
# END LOOP TO PERFORM LIBRARY-LEVEL ACTIONS
################################################################################

################################################################################
# CONCATENATE SAMPLES
################################################################################
# TODO could move this first step up above any loops (no else)
# TODO MOVE THE VARIABLE ASSIGNMENT TO TOP; MOVE MKDIR TO TOP OF CONCAT IF LOOP
echo $(date +%Y-%m-%d\ %H:%M) "Concatenating fasta files..."
CONCAT_DIR="${OUTPUT_DIR}"/all_lib
mkdir "${CONCAT_DIR}"
CONCAT_FILE="${CONCAT_DIR}"/1_demult_concat.fasta

# TODO could move this into above loop after demultiplexing?
for CURRENT_ID1_NAME in "${ID1_NAMES[@]}"; do

	ID1_OUTPUT_DIR="${OUTPUT_DIR}"/${CURRENT_ID1_NAME##*/}

	for IND_SEQ in $IND2S; do
		cat "${ID1_OUTPUT_DIR}"/demultiplexed/tag_"${IND_SEQ}"/2_notags.fasta >> "${CONCAT_FILE}"
	done

	echo $(date +%Y-%m-%d\ %H:%M) "Compressing fasta files..."
	find "${ID1_OUTPUT_DIR}" -type f -name '*.fasta' -exec ${ZIPPER} "{}" \;
	echo $(date +%Y-%m-%d\ %H:%M) "fasta files compressed."

done
echo


################################################################################
# PRIMER REMOVAL
################################################################################
source "${SCRIPT_DIR}"/scripts/primer_removal.sh

################################################################################
# CONSOLIDATE IDENTICAL SEQUENCES (DEREPLICATION)
################################################################################
source "${SCRIPT_DIR}"/scripts/dereplication.sh


##############################################################################
# CHECK FOR CHIMERAS
##############################################################################
if [[ "${remove_chimeras}" = "YES" ]] ; then
echo $(date +%Y-%m-%d\ %H:%M) 'Looking for chimeras in duplicate fasta file using vsearch'
source "${SCRIPT_DIR}"/scripts/chimera_check.sh "${duplicate_fasta}"
clustering_input="${chimera_free_fasta}"
echo
else
clustering_input="${duplicate_fasta}"
fi





################################################################################
# CLUSTER OTUS
################################################################################
# Note that identical (duplicate) sequences were consolidated earlier;
# This step outputs a file (*.uc) that lists, for every sequence, which sequence it clusters with
if [ "$CLUSTER_OTUS" = "NO" ]; then
	BLAST_INPUT="${clustering_input}"
else
	case "${cluster_method}" in

	    "swarm" )

	        echo $(date +%Y-%m-%d\ %H:%M) 'Clustering sequences into OTUs using swarm'
	        source "${SCRIPT_DIR}"/scripts/OTU_clustering/cluster_swarm.sh "${clustering_input}"
					echo

	    ;;

	    "vsearch" )

	        # echo $(date +%Y-%m-%d\ %H:%M) 'Clustering sequences into OTUs using vsearch'
	        # source "${SCRIPT_DIR}"/scripts/OTU_clustering/cluster_vsearch.sh "${duplicate_fasta}"
					echo "Sorry, OTU clustering with vsearch has not been implemented yet."
					echo $(date +%Y-%m-%d\ %H:%M) 'Clustering sequences into OTUs using swarm'
	        source "${SCRIPT_DIR}"/scripts/OTU_clustering/cluster_swarm.sh "${clustering_input}"
					echo

	    ;;

	    "usearch" )

	        echo $(date +%Y-%m-%d\ %H:%M) 'Clustering sequences into OTUs using usearch'
	        source "${SCRIPT_DIR}"/scripts/OTU_clustering/cluster_usearch.sh "${clustering_input}"
					echo

	    ;;

	    * )

	        echo "${cluster_method}" 'is an invalid clustering method.'
	        echo 'Must be one of swarm, vsearch, usearch, or none.'
	        echo $(date +%Y-%m-%d\ %H:%M) 'Clustering sequences into OTUs using swarm'
	        source "${SCRIPT_DIR}"/scripts/OTU_clustering/cluster_swarm.sh "${clustering_input}"
					echo


	    ;;

	esac

	# check that dup to otu map is greater than 12 bytes
	minsize=12
	size_dup_otu_map=$(wc -c <"${dup_otu_map}")
	if [ $size_dup_otu_map -lt $minsize ]; then
	    echo 'There was an error generating the dup-to-otu map.'
			echo
	fi


	# Assign the path for the OTU table
	# OTU_table="${dir_out}"/OTU_table.csv

	# Convert duplicate table to OTU table using R script (arguments: (1) duplicate table, (2) dup to otu table, (3) otu table path
	Rscript "$SCRIPT_DIR/scripts/dup_to_OTU_table.R" "${duplicate_table}" "${dup_otu_map}" "${OTU_table}"

	# check if OTU table and OTU fasta exist (and/or are of size gt 1?)
	if [[ ! -s "${OTU_fasta}" ]] ; then
	    echo 'There was a problem generating the OTU fasta file. It is empty or absent.'
	    echo 'Aborting script.'
	    exit
	fi
	if [[ ! -s "${OTU_table}" ]] ; then
	    echo 'There was a problem generating the OTU table. It is empty or absent.'
	    echo 'Aborting script.'
	    exit
	fi

fi


################################################################################
# CLEAN UP
################################################################################
if [ "$PERFORM_CLEANUP" = "YES" ]; then
	echo $(date +%Y-%m-%d\ %H:%M) "Compressing fasta, fastq, and xml files..."
	find "${OUTPUT_DIR}" -type f -name '*.fasta' -exec ${ZIPPER} "{}" \;
	find "${OUTPUT_DIR}" -type f -name '*.fastq' -exec ${ZIPPER} "{}" \;
	find "${OUTPUT_DIR}" -type f -name '*.xml' -exec ${ZIPPER} "{}" \;
	echo $(date +%Y-%m-%d\ %H:%M) "Cleanup performed."
else
	echo $(date +%Y-%m-%d\ %H:%M) "Cleanup not performed."
fi

FINISH_TIME=$(date +%Y%m%d_%H%M)

echo 'Pipeline finished! Started at' $START_TIME 'and finished at' $FINISH_TIME | mail -s "banzai is finished" "${EMAIL_ADDRESS}"

################################################################################
# WRITE SUMMARY
################################################################################
SUMMARY_FILE="${OUTPUT_DIR}"/summary.txt
echo "Writing summary file..."
source "${SCRIPT_DIR}"/scripts/summarize.sh "${LOGFILE}" > "${SUMMARY_FILE}"
echo "Summary written to:"
echo "${SUMMARY_FILE}"
echo

################################################################################
# EXIT
################################################################################
echo -e '\n'$(date +%Y-%m-%d\ %H:%M)'\tAll finished! Why not treat yourself to a...\n'
echo
echo -e '\t~~~ MAI TAI ~~~'
echo -e '\t2 oz\taged rum'
echo -e '\t0.75 oz\tfresh squeezed lime juice'
echo -e '\t0.5 oz\torgeat'
echo -e '\t0.5 oz\ttriple sec'
echo -e '\t0.25 oz\tsimple syrup'
echo -e '\tShake, strain, and enjoy!' '\xf0\x9f\x8d\xb9\x0a''\n'
