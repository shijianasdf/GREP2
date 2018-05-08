#' A complete pipeline to process GEO RNA-seq data
#'
#' \code{process_geo_rnaseq} downloads and processes GEO RNA-seq data for a given GEO series accession ID. It filters metadata for RNA-seq samples only. 
#' We use SRA toolkit for downloading SRA data, Trimmomatic for read trimming (optional), and Salmon for read mapping. 
#'
#' @param geo_series_acc GEO series accession ID.
#' @param destdir directory where all the results will be saved.
#' @param ascp logical, whether to use Aspera connect to download SRA run files. If FALSE, then wget will be used to download files which might be slower than \code{'ascp'} download.
#' @param prefetch_workspace directory where SRA run files will be downloaded. This parameter is needed when \code{ascp=TRUE}. 
#' The location of this directory can be found by going to the aspera directory (/.aspera/connect/bin/) and typing \code{'vdb-config -i'}.
#' A new window will pop-up and under the \code{'Workspace Name'}, you will find the location. Usually the default is \code{'/home/username/ncbi/public'}.
#' @param ascp_path path to the Aspera software. 
#' @param get_sra_file logical, whether to download SRA file first and get fastq files afterwards.
#' @param trim_fastq logical, whether to trim fastq file. 
#' @param trimmomatic_path path to Trimmomatic software.
#' @param index_dir directory of the indexing files needed for read mapping using Salmon. See \link[GREP2]{build_index}.
#' @param species name of the species. Only \code{'human'}, \code{'mouse'}, and \code{'rat'} are allowed to use.
#' @param countsFromAbundance whether to generate counts based on abundance. Available options are: \code{'no'}, 
#' \code{'scaledTPM'} (abundance based estimated counts scaled up to library size), 
#' \code{'lengthScaledTPM'} (default, scaled using the average transcript length over samples and library size). See Bioconductor package \link[tximport]{tximport} for further details.
#' @param n_thread number of cores to use.
#'
#' @return a list of metadata from GEO and SRA saved in the \code{destdir}. Another list of gene and transcript level estimated counts summarized by 
#' Bioconductor package \code{'tximport'} is also saved in the \code{destdir}.
#' 
#' @references 
#' 
#' Rob Patro, Geet Duggal, Michael I. Love, Rafael A. Irizarry, and Carl Kingsford (2017):
#' Salmon provides fast and bias-aware quantification of transcript expression. Nature methods, 14(4), 417.
#' \url{https://www.nature.com/articles/nmeth.4197}
#'
#' Charlotte Soneson, Michael I. Love, Mark D. Robinson (2015):
#' Differential analyses for RNA-seq: transcript-level estimates
#' improve gene-level inferences. F1000Research.
#' \url{http://dx.doi.org/10.12688/f1000research.7563.1}
#' 
#' Philip Ewels, Måns Magnusson, Sverker Lundin, and Max Käller (2016):
#' MultiQC: summarize analysis results for multiple tools and samples 
#' in a single report. Bioinformatics, 32(19), 3047-3048.
#' \url{https://doi.org/10.1093/bioinformatics/btw354} 
#'
#' @examples
#' process_geo_rnaseq (geo_series_acc="GSE107363", destdir="/home", ascp=TRUE, prefetch_workspace="/home/username/ncbi/public",
#' ascp_path="/home/user/.aspera/", get_sra_file=FALSE, trim_fastq=FALSE, trimmomatic_path=NULL, index_dir="/home/human_transcripts_release91_index/",
#' species="human", countsFromAbundance = "lengthScaledTPM", n_thread=2)
#'
#' @importFrom parallel mclapply
#'
#' @export 
process_geo_rnaseq <- function(geo_series_acc, 
								destdir, 
								ascp=TRUE, 
								prefetch_workspace, 
								ascp_path, 
								get_sra_file=FALSE, 
								trim_fastq=FALSE, 
								trimmomatic_path=NULL, 
								index_dir, 
								species=c("human","mouse","rat"), 
								countsFromAbundance = c("no","scaledTPM","lengthScaledTPM"), 
								n_thread=2) {


	system(paste0("mkdir ",destdir,"/",geo_series_acc))
	destdir <- paste0(destdir,"/",geo_series_acc,"/")
	setwd(destdir)
	
	cat(paste("Downloading metadata... ",Sys.time(),"\n",sep=""))
	#source("/opt/raid10/genomics/naim/myGithub/GREP2/R/get_metadata.R")
	metadata <- get_metadata(geo_series_acc)
	metadata$metadata_geo <- metadata$metadata_geo[which(metadata$metadata_geo$library_strategy=="RNA-Seq"),]
	metadata$metadata_sra <- metadata$metadata_sra[which(metadata$metadata_sra$LibraryStrategy=="RNA-Seq"),]
	save(metadata, file="metadata.RData")
	
	srr_id <- metadata$metadata_sra$Run
	library_layout <- metadata$metadata_sra$LibraryLayout
	instrument <- metadata$metadata_geo$instrument_model
	countsFromAbundance <- match.arg(countsFromAbundance, c("no","scaledTPM","lengthScaledTPM"))
	species <- match.arg(species, c("human","mouse","rat"))

	if(get_sra_file) {
		cat(paste("Downloading SRA files... ",Sys.time(),"\n",sep=""))
		#source("/opt/raid10/genomics/naim/myGithub/GREP2/R/get_srr.R")
		parallel::mclapply(1: length(srr_id),function(i) {
			get_srr(srr_id[i], destdir, ascp, prefetch_workspace, ascp_path)
		}, mc.cores=n_thread)
	}
	
	#source("/opt/raid10/genomics/naim/myGithub/GREP2/R/get_fastq.R")
	if(ascp){
		cat(paste("Downloading fastq files... ",Sys.time(),"\n",sep=""))
		sra_files_dir <- paste0(prefetch_workspace,"/sra/")
		parallel::mclapply(1: length(srr_id),function(i) {
			get_fastq(srr_id[i], library_layout[i], get_sra_file, sra_files_dir, n_thread, destdir)
		}, mc.cores=n_thread)
	} else {
		cat(paste("Step 3: Downloading fastq files... ",Sys.time(),"\n",sep=""))
		parallel::mclapply(1: length(srr_id),function(i) {
			sra_files_dir <- paste0(destdir,"/",srr_id[i])
			get_fastq(srr_id[i], library_layout[i], get_sra_file, sra_files_dir, n_thread, destdir)
		}, mc.cores=n_thread)
	}

	cat(paste("Running FastQC... ",Sys.time(),"\n",sep=""))
	#source("/opt/raid10/genomics/naim/myGithub/GREP2/R/run_fastqc.R")
	parallel::mclapply(1: length(srr_id),function(i) {
		fastq_dir <- paste0(destdir,"/",srr_id[i])
		run_fastqc(destdir, fastq_dir, n_thread )
	}, mc.cores=n_thread)

	if(trim_fastq){
		cat(paste("Trimming fastq... ",Sys.time(),"\n",sep=""))
		#source("/opt/raid10/genomics/naim/myGithub/GREP2/R/trim_fastq.R")
		parallel::mclapply(1: length(srr_id),function(i) {
			fastq_dir <- paste0(destdir,"/",srr_id[i])
			trim_fastq (srr_id[i], fastq_dir, instrument, trimmomatic_path, library_layout[i], n_thread)
		}, mc.cores=n_thread)
	}
	use_trimmed_fastq= if(trim_fastq){TRUE} else {FALSE}
	
	cat(paste("Run Salmon and get counts... ",Sys.time(),"\n",sep=""))
	#source("/opt/raid10/genomics/naim/myGithub/GREP2/R/run_salmon.R")
	parallel::mclapply(1: length(srr_id),function(i) {
		fastq_dir <- paste0(destdir,"/",srr_id[i])
		run_salmon (srr_id[i], library_layout[i], index_dir, destdir, fastq_dir, use_trimmed_fastq, n_thread)
	}, mc.cores=n_thread)
	
	#source("/opt/raid10/genomics/naim/myGithub/GREP2/R/run_tximport.R")	
	salmon_dir <- paste0(destdir,"/salmon/")
	counts_data_list <- run_tximport (srr_id, species, salmon_dir, countsFromAbundance)		
	save(counts_data_list, file="counts_data_list.RData")
	
	cat(paste("Run MultiQC... ",Sys.time(),"\n",sep=""))
	#source("/opt/raid10/genomics/naim/myGithub/GREP2/R/run_multiqc.R")
	fastqc_dir <- paste0(destdir,"/fastqc/")
	run_multiqc (fastqc_dir, salmon_dir, destdir)
	
	cat(paste("Processing completed. ",Sys.time(),"\n",sep=""))
	print(sessionInfo())

}