#!/bin/bash
#
#  CLAP - CLIP Analysis Pipeline
# 
#  Simon H. Rasmussen
#  Bioinformatics Centre
#  University of Copenhagen
#
#  Mireya Plass
#  Max Delbrück Center
#  Berlin, Germany
#
####################################################################################################
####################################################################################################
# TODO: Implement time stamps and print header
#start=`date +%s`
#stuff
#end=`date +%s`
#
#runtime=$((`date +%s`-start)) sec
#
############
start=`date +%s`
echo "#################### CLAP - CLIP Analysis Pipeline ####################"
echo "#######################################################################"
echo "#######################################################################"


trap "" 1
if [ $# -lt 14 ]
  then
    echo "ARGUMENTS:" 
    echo "\$1: Filename"
    echo "\$2: Remove adapters?" 
    echo "    \"\": If no adapter"
    echo "    Adapter sequence, ex: ACCTGCA..."
    echo "\$3: Sequence fixed barcode" 
    echo "\$4: length of random barcode"
    echo "\$5: Remove duplicates?"
    echo "    0: No" 
    echo "    1: Yes"  
    echo "\$6: Type of analysis" 
    echo "    1: fixed barcode, random barcodes"
    echo "    2: no fixed barcode, no random barcodes"
    echo "    3: only fixed barcode, no random barcodes"
    echo "    4: no fixed barcode, only random barcodes"
    echo "\$7: UCSC Custom Tracks (bedGraph tracks)"
    echo "    0: No UCSC custom tracks" 
    echo "    1: UCSC custom tracks" 
    echo "\$8: Stranded protocol?"
    echo "    0: Strandless" 
    echo "    1: Stranded" 
    echo "\$9: Index"
    echo "    1: hg19 genome index" 
    echo "    2: hg19 genome index + exon junction index" 
    echo "\$10: Model"
    echo "    0: Model T>C conversions (PAR-CLIP), conversion prob 0.125" 
    echo "    1: No model (RNA-Seq, iCLIP or HITS-CLIP)" 
    echo "\$11: Output name"
    echo "\$12: Quality scores"
    echo "    0: Phread 64" 
    echo "    1: Phread 33" 
    echo "\$13: Number of threads?"
    echo "    Input number of threads"
    echo "\$14: Peak calling (pyicoclip modFDR)?"
    echo "    0: No"
    echo "    1: Yes"
    exit 0
fi

#set -x
set -e

if [ ${12} -eq 0 ]
then 
    # Trimming option
    Qtype=64  # illumina Phred+64
    #Qtype=65  # illumina Phred+64 BGI

    # BWA option
    phreadOpt=" -I "
else
    # Trimming option
    Qtype=32  # illumina Phred+33

    # BWA option
    phreadOpt=""
fi

if [ ${13} -lt 1 ]
then
    # Number of threads
    threads=1
else
    threads=${13}
fi
   
barcode=$3
trim=$4

# Q = 1 - P, Q is the fraction you expect not to map due to contamination, see Kerpedjiev et al 2014.
P=0.5
PP=0.99
pid=$$

# Base dir
BASE=$(pwd)
scripts=$BASE"/scripts"

# Configurations
# PSSM path
#bwa=bwa
# Absolute path to binary
bwa=$BASE/../bwa-pssm/bwa
echo "#################### Testing if pipeline is correctly configured..."

if [ -z $(which $bwa) ]
then
    echo
    echo "#################### bwa-pssm mapper could not be located here:" $bwa
    echo "#################### Please correct path"
exit
else
    echo 
    echo "#################### bwa-pssm mapper located" 
fi

# Pyicos Path
pyicos=pyicoclip

if [ -z $(which $pyicos) ]
then
    echo "#################### pyicosclip could not be located here:" $pyicos
    echo "######### Please correct path."
exit
else 
    echo "#################### pyicosclip located"
fi

bedTools=bedtools
if [ -z $(which $bedTools) ]
then 
    echo "#################### bedtools could not be located here" $bedTools 
    echo "#################### Please correct path"
    echo
exit
else
    echo "#################### bedTools located"
    echo
fi


# Mapping index location
# Ensembl version
ver=87
species=homo_sapiens

# Old data
#idx1=$BASE"/resources/hg19.fa"
#idx3=$BASE"/resources/ensembl70_ej.fa"
#exon_annot=$BASE"/resources/ensembl70.exon.long_nooverlap.txt"

idx1=$BASE/resources/ensembl.$species.$ver.fa
idx3=$BASE/resources/ensembl.$species.$ver.ej.fa
exon_annot=$BASE/resources/ensembl.$species.$ver.nooverlap.exons.long.txt

if [ ${#12} -gt 0 ]
then
    outFolder=$(pwd)/${11}"_"$pid
else
    outFolder=$(pwd)/${f1%.*}"_"$pid
fi

mkdir $outFolder
trap "echo '###################### Output directory: '" 0
trap "echo $outFolder" 0

#exec 1> $outFolder/mapping_pipe.log
#exec 2>&1    

# Min read length - species dependent
length=20

# Treads
T=$threads
# heap size
H=400
# seed length, seeding disabled
L=1024
# Error prob binomial model see original BWA paper
E=0.04
error_model=resources/error_model_125.txt

# Filenames 
file_list=$1
FILE=$(basename $file_list)
FILE_NAME=$(dirname $file_list)
    
if [ $6 -eq 2 -o $6 -eq 4 ]
then
    if [ "$barcode" == "" ]
    then
	barcode="nobc"
    fi
fi
ftmp=$barcode"_assigned_"$FILE
f2=$barcode"_noADPT_"${FILE%.*}.fastq
f3=$barcode"_noDUPS_"${FILE%.*}.fastq
final_bed=$barcode"_merged_"${FILE%.*}.bed
clusters=$barcode"_"${FILE%.*}"_clusters".bed

if [ $6 -eq 1 -o $6 -eq 3 ]
then
    # Remove barcode and select data of max edit dist 1, offset is at what position the fixed barcode starts XXXTTGTXX_READ_ > primer XXACAAXXX
    echo
    echo "#################### Removing barcodes and pick out data "
    

    cd $outFolder
    cat $FILE_NAME/$FILE|$scripts/get_data_from_barcode.py -p $barcode -o 3 -m 1 1> $outFolder/$ftmp
    cd ..
else
    echo "#################### Data has no fixed barcodes ##"

    cp $FILE_NAME/$FILE $outFolder/$ftmp
fi

if [ ${#2} -gt 0 ]
then
    # Remove Adaptors
   
    echo "#################### Removing Adapters "
    echo "#################### Runtime " $((`date +%s`-start)) sec
    echo
    adapterS=$2
    cd $outFolder
    $scripts/adapterHMM_multiPY.py -q $Qtype -s $adapterS -f $outFolder/$ftmp -o $outFolder/$f2 -l $(($length+$trim)) -p $threads
    rm *_adaptor_hmm.imod
#    rm $outFolder/$ftmp
    cd ..
else
    echo
    echo "#################### Will not remove Adaptors "
    echo "#################### Runtime " $((`date +%s`-start)) sec
    echo
    mv $outFolder/$ftmp $outFolder/$f2
fi
# Remove duplicates
if [ $6 -eq 1 -o $6 -eq 4 ]
then
    echo
    echo "#################### Remove duplicates using random barcodes "
    echo "#################### Runtime " $((`date +%s`-start)) sec
    echo
else
    echo
    echo "#################### Remove duplicates without using random barcodes "
    echo "#################### Runtime " $((`date +%s`-start)) sec
    echo
    trim=0
fi

if [ $5 -eq 1 ]
then
    cd $outFolder
    $scripts/duplication_barcode.py -f $outFolder/$f2 -t $trim > $outFolder/$f3
    cd ..
else
    mv $outFolder/$f2 $outFolder/$f3
fi
rm $outFolder/$f2

# cut suffix .fastq

map_reads=${f3%.*}
map_exon=$map_reads.ej
echo
echo "#################### Mapping to the genome with bwa-pssm " 

if [ ${10} -eq 0 ]
then

echo "#################### Use substituion model " 
    echo "#################### Runtime " $((`date +%s`-start)) sec
echo
    # Map with error model
    $bwa pssm -n $E -l $L -m $H -t $T -P $P $phreadOpt -G $error_model $idx1 $outFolder/$map_reads.fastq  > $outFolder/$map_reads.sai
else

echo "#################### Do not use substitution model " 
    echo "#################### Runtime " $((`date +%s`-start)) sec
echo
    $bwa pssm -n $E -l $L -m $H -t $T -P $P $phreadOpt $idx1 $outFolder/$map_reads.fastq  > $outFolder/$map_reads.sai
#    $bwa samse -f $outFolder/$map_reads.sam $idx1 $outFolder/$map_reads.sai $outFolder/$map_reads.fastq
#    rm $outFolder/$map_reads.sai
#    cat $outFolder/$map_reads.sam|$scripts/read_stats.py -t $PP 1> $outFolder/$map_reads.mappingstats.txt
fi
$bwa samse -f $outFolder/$map_reads.sam $idx1 $outFolder/$map_reads.sai $outFolder/$map_reads.fastq
rm $outFolder/$map_reads.sai
echo
echo "#################### Genome mapping statistics "
echo "#################### Runtime " $((`date +%s`-start)) sec
echo
cat $outFolder/$map_reads.sam|$scripts/read_stats.py -t $PP 1> $outFolder/$map_reads.mappingstats.txt
if [ $9 -eq 2 ]
then
echo
echo "#################### Mapping to the exon junctions with bwa-pssm " 
echo "#################### Runtime " $((`date +%s`-start)) sec
    # Exon-junction mapping
    $scripts/select_unmapped_reads.pl -f $outFolder/$map_reads.fastq -s $outFolder/$map_reads.sam  > $outFolder/$map_exon.fastq
    
    if [ ${10} -eq 0 ]
    then	
	echo "#################### Use substituion model " 
	echo "#################### Runtime " $((`date +%s`-start)) sec
	echo
	$bwa pssm -n $E -l $L -m $H -t $T -P $P $phreadOpt -G $error_model $idx3 $outFolder/$map_exon.fastq > $outFolder/$map_exon.sai
    else
	echo "#################### Do not use substitution model " 
	echo "#################### Runtime " $((`date +%s`-start)) sec
	echo
	$bwa pssm -n $E -l $L -m $H -t $T -P $P $phreadOpt $idx3 $outFolder/$map_exon.fastq > $outFolder/$map_exon.sai
    fi
    $bwa samse -f $outFolder/$map_exon.sam $idx3 $outFolder/$map_exon.sai $outFolder/$map_exon.fastq
    rm $outFolder/$map_exon.sai
    
    echo
    echo "#################### Exon junction mapping statistics "
    echo "#################### Runtime " $((`date +%s`-start)) sec
    echo
    cat $outFolder/$map_exon.sam |$scripts/read_stats.py -t $PP -j 1> $outFolder/$map_exon.mappingstats.txt
fi
#done
# Make bed-files 
# Genome
$BASE/scripts/parse_sam_files_final.pl -p $idx1 -t pssm -c $PP -f $outFolder/$map_reads.sam -o $outFolder/$map_reads.bed -a
if [ $9 -eq 2 ]
then
    # Exon junctions
    $BASE/scripts/parse_sam_files_ej_final.pl -p $idx3 -t pssm -c $PP -f $outFolder/$map_exon.sam -o $outFolder/$map_exon.bed -a
fi
# peak Calling
echo
echo "#################### Calculate False Discovery rate of read clusters with Pyicosclip " 
echo "#################### Runtime " $((`date +%s`-start)) sec
echo

if [ $9 -eq 1 ]
then
    # Genome reads
    peak_in=$map_reads.bed
    peak_out=$map_reads.pk
    # rename genome reads file
    cat $outFolder/$map_reads.bed  > $outFolder/$final_bed
    if [ ${14} -ne 0 ]
    then
	if [ $8 -eq 0 ]
	then
	    $pyicos -f 'bed' -F 'bed_pk' --p-value 0.01 --region $exon_annot --stranded $outFolder/$peak_in $outFolder/$peak_out 
	else
	    # not stranded
	    $pyicos -f 'bed' -F 'bed_pk'  --p-value 0.01 --region $exon_annot $outFolder/$peak_in $outFolder/$peak_out 
	fi
	# not stranded
    fi
fi

if [ $9 -eq 2 ]
then
    # Genome reads
    peak_in=$map_reads.both.bed
    peak_out=$map_reads.both.pk
    
    # exon junctions
    #peak_in2=$map_exon.bed
    #peak_out2=$map_exon.pk

    cat $outFolder/$map_reads.bed $outFolder/$map_exon.bed > $outFolder/$peak_in
#    head  $outFolder/$map_exon.bed
    #rm $outFolder/$map_reads.bed $outFolder/$map_exon.bed 
    
    if [ ${14} -ne 0 ]
    then
	if [ $8 -eq 0 ]
	then
	    $pyicos -f 'bed' -F 'bed_pk' --p-value 0.01 --region $exon_annot --stranded $outFolder/$peak_in $outFolder/$peak_out 
	else
	    # not stranded
	    $pyicos -f 'bed' -F 'bed_pk' --p-value  0.01 --region $exon_annot $outFolder/$peak_in $outFolder/$peak_out 
	fi
	# not stranded
    fi
    
    # Merge reads from genome and exon junctions
   # cat $outFolder/$peak_in
   # cat $outFolder/$peak_out
fi
echo
echo "#################### Producing UCSC custom tracks with significant peaks (bed-track format) "

if [ $7 -eq 1 ]
then
    if [ $8 -eq 1 ]
    then
	echo "#################### UCSC custom tracks for stranded protocol..."
	echo "#################### Runtime " $((`date +%s`-start)) sec
	cat $outFolder/$peak_out|$scripts/pk2bedGraph_info.pl -c 1,2,4,6 -s - -n "-_strand_"$name -d "Clusters on minus-strand" > $outFolder/"UCSC_-_"${FILE%.*}".track"
	cat $outFolder/$peak_out | $scripts/pk2bedGraph_info.pl -c 1,2,4,6 -s + -n "+_strand_"$name -d  "Clusters on plus-strand" > $outFolder/"UCSC_+_"${FILE%.*}".track"
	
	gzip $outFolder/"UCSC_-_"${FILE%.*}".track"
	gzip $outFolder/"UCSC_+_"${FILE%.*}".track"
    else
	echo "#################### UCSC custom track for strandless protocol..."
	echo "#################### Runtime " $((`date +%s`-start)) sec
	cat $outFolder/$peak_out | $scripts/pk2bedGraph_info.pl -c 1,2,4,6 -s "+" -n $name -d "Clusters on both strands" > $outFolder/"UCSC_mp_"${FILE%.*}".track"
	gzip $outFolder/"UCSC_-+_"${FILE%.*}".track"
    fi
fi

#done
