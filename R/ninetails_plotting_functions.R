
#' Draws an entire squiggle for given read.
#'
#' Creates segmented plot of raw/rescaled ONT RNA signal (with or without moves).
#' A standalone function; does not rely on any other preprocessing, depends
#' solely on Nanopolish, Guppy and fast5 input.
#'
#' The output plot includes an entire squiggle corresponding to the given ONT
#' read. Vertical lines mark the 5' (navy blue) and 3' (red) termini of polyA
#' tail according to the Nanopolish polyA function. In order to maintain
#' readability of the graph (and to avoid plotting high cliffs - e.g. jets
#' of the signal caused by a sudden surge of current in the sensor)
#' the signal is winsorised.
#'
#' Moves may be plotted only for reads basecalled by Guppy basecaller.
#' Otherwise the function will throw an error.
#'
#' @param readname character string. Name of the given read within the
#' analyzed dataset.
#'
#' @param nanopolish character string. Full path of the .tsv file produced
#' by nanopolish polya function.
#'
#' @param sequencing_summary character string. Full path of the .txt file
#' with sequencing summary.
#'
#' @param workspace character string. Full path of the directory to search the
#' basecalled fast5 files in. The Fast5 files have to be multi-fast5 file.
#'
#' @param basecall_group character string ("Basecall_1D_000" is set
#' as a default). Name of the level in the Fast5 file hierarchy from
#' which the data should be extracted.
#'
#' @param moves logical [TRUE/FALSE]. If TRUE, moves would be plotted in
#' the background as vertical bars/gaps (for values 0/1, respectively)
#' and the signal (squiggle) would be plotted in the foreground.
#' Otherwise, only the signal would be plotted. As a default,
#' "FALSE" value is set.
#'
#' @param rescale logical [TRUE/FALSE]. If TRUE, the signal will be rescaled for
#' picoamps (pA) per second (s). If FALSE, raw signal per position will be
#' plotted. As a default, the "FALSE" value is set.
#'
#' @return ggplot2 object with squiggle plot depicting nanopore read signal.
#' @export
#'
#' @examples
#' \dontrun{
#'
#'plot <- ninetails::plot_squiggle(
#'  readname = "0226b5df-f9e5-4774-bbee-7719676f2ceb",
#'  nanopolish = system.file('extdata',
#'                           'test_data',
#'                           'nanopolish_output.tsv',
#'                           package = 'ninetails'),
#'  sequencing_summary = system.file('extdata',
#'                                   'test_data',
#'                                   'sequencing_summary.txt',
#'                                   package = 'ninetails'),
#'  workspace = system.file('extdata',
#'                          'test_data',
#'                          'basecalled_fast5',
#'                          package = 'ninetails'),
#'  basecall_group = 'Basecall_1D_000',
#'  moves = FALSE,
#'  rescale = TRUE)
#'
#' print(plot)
#'
#'}
#

plot_squiggle <- function(readname,
                          nanopolish,
                          sequencing_summary,
                          workspace,
                          basecall_group = "Basecall_1D_000",
                          moves=FALSE,
                          rescale=FALSE){

  # variable binding (suppressing R CMD check from throwing an error)
  polya_start <- transcript_start <- adapter_start <- leader_start <- filename <- read_id <- position <- time <- pA <- segment <- NULL


  #Assertions
  if (missing(readname)) {
    stop("Readname [string] is missing. Please provide a valid readname argument.", call. =FALSE)
  }

  if (missing(workspace)) {
    stop("Directory [string] with basecalled fast5s is missing. Please provide a valid workspace argument.", call. =FALSE)
  }
  if (missing(sequencing_summary)) {
    stop("Sequencing summary file [string] is missing. Please provide a valid sequencing_summary argument.", .call = FALSE)
  }

  if (missing(nanopolish)) {
    stop("Nanopolish polya output [string] is missing. Please provide a valid nanopolish argument.", .call = FALSE)
  }


  if (checkmate::test_string(nanopolish)) {
    # if string provided as an argument, read from file
    # handle nanopolish
    assertthat::assert_that(assertive::is_existing_file(nanopolish), msg=paste0("File ",nanopolish," does not exist",sep=""))
    nanopolish <- vroom::vroom(nanopolish, col_select=c(readname, polya_start, transcript_start, adapter_start, leader_start), show_col_types = FALSE)
    colnames(nanopolish)[1] <- "read_id" #because there was conflict with the same vars
  }

  #else: make sure that nanopolish is an  object with rows
  assertthat::assert_that(assertive::has_rows(nanopolish), msg = "Empty data frame provided as an input (nanopolish). Please provide valid input")


  nanopolish <- nanopolish[nanopolish$read_id==readname,]
  adapter_start_position <- nanopolish$adapter_start
  leader_start_position <- nanopolish$leader_start
  polya_start_position <- nanopolish$polya_start
  transcript_start_position <-nanopolish$transcript_start
  #define polya end position
  polya_end_position <- transcript_start_position -1


  if (checkmate::test_string(sequencing_summary)) {
    #handle sequencing summary
    assertthat::assert_that(assertive::is_existing_file(sequencing_summary), msg=paste0("File ",sequencing_summary," does not exist",sep=""))
    sequencing_summary <- vroom::vroom(sequencing_summary, col_select = c(filename, read_id), show_col_types = FALSE)
  }

  sequencing_summary <- sequencing_summary[sequencing_summary$read_id==readname,]

  assertthat::assert_that(assertive::has_rows(sequencing_summary), msg = "Empty data frame provided as an input (sequencing_summary). Please provide valid input")

  # Extract data from fast5 file
  fast5_file <- sequencing_summary$filename
  fast5_readname <- paste0("read_",readname) # in fast5 file structure each readname has suffix "read_"
  fast5_file_path <-file.path(workspace, fast5_file) #this is path to browsed fast5 file


  signal <- rhdf5::h5read(file.path(fast5_file_path),paste0(fast5_readname,"/Raw/Signal"))
  signal <- as.vector(signal) # initially signal is stored as an array, I prefer to vectorize it for further manipulations with dframes

  # retrieving sequence, traces & move tables
  BaseCalled_template <- rhdf5::h5read(fast5_file_path,paste0(fast5_readname,"/Analyses/", basecall_group, "/BaseCalled_template"))
  move <- BaseCalled_template$Move #how the basecaller "moves" through the called sequence, and allows for a mapping from basecall to raw data
  move <- as.numeric(move) # change data type as moves are originally stored as raw

  #read parameters stored in channel_id group
  channel_id <- rhdf5::h5readAttributes(fast5_file_path,paste0(fast5_readname,"/channel_id")) # parent dir for attributes (within fast5 file)
  digitisation <- channel_id$digitisation # number of quantisation levels in the analog to digital converter
  digitisation <- as.integer(digitisation)
  offset <- channel_id$offset # analog to digital signal error
  offset <- as.integer(offset)
  range <- channel_id$range # difference between the smallest and greatest values
  range <- as.integer(range)
  sampling_rate <- channel_id$sampling_rate # number of data points collected per second
  sampling_rate <- as.integer(sampling_rate)

  #read parameters (attrs) stored in basecall_1d_template
  basecall_1d_template <- rhdf5::h5readAttributes(fast5_file_path,paste0(fast5_readname,"/Analyses/", basecall_group, "/Summary/basecall_1d_template")) # parent dir for attributes (within fast5)
  stride <- basecall_1d_template$block_stride #  this parameter allows to sample data elements along a dimension
  called_events <- basecall_1d_template$called_events # number of events (nanopore translocations) recorded by device for given read

  # close all handled instances (groups, attrs) of fast5 file
  rhdf5::h5closeAll()

  #winsorize signal (remove cliffs) thanks to this, all signals are plotted without current jets
  signal_q <- stats::quantile(x=signal, probs=c(0.002, 0.998), na.rm=TRUE, type=7)
  minimal_val <- signal_q[1L]
  maximal_val <- signal_q[2L]
  signal[signal<minimal_val] <- minimal_val
  signal[signal>maximal_val] <- maximal_val
  signal <- as.integer(signal)


  # number of events expanded for whole signal vec (this is estimation of signal length, however keep in mind that decimal values are ignored)
  number_of_events <- called_events * stride
  signal_length <- length(signal)

  #handling move data
  moves_sample_wise_vector <- c(rep(move, each=stride), rep(NA, signal_length - number_of_events))

  #creating signal df
  signal_df <- data.frame(position=seq(1,signal_length,1), signal=signal[1:signal_length], moves=moves_sample_wise_vector) # this is signal converted to dframe


  # signal segmentation factor
  #adapter sequence
  signal_df$segment[signal_df$position < polya_start_position] <- "adapter"
  #transcript sequence
  signal_df$segment[signal_df$position >= transcript_start_position] <- "transcript"
  #polya sequence
  signal_df$segment[signal_df$position >= polya_start_position & signal_df$position <= polya_end_position] <- "poly(A)"
  signal_df$segment <- as.factor(signal_df$segment)


  # plotting squiggle

  if (rescale==TRUE) {
    #additional df cols need for rescaling data
    signal_df <- dplyr::mutate(signal_df, time = position/sampling_rate)
    signal_df <- dplyr::mutate(signal_df, pA = ((signal + offset) * (range/digitisation)))
    #plotting signal rescaled to picoamps per second
    squiggle <- ggplot2::ggplot(data = signal_df, ggplot2::aes(x = time)) +
      ggplot2::geom_line(ggplot2::aes(y = pA, color = segment)) + ggplot2::theme_bw() +
      ggplot2::scale_colour_manual(values = c("#089bcc", "#f56042", "#3a414d"))
    g.line <- ggplot2::geom_vline(xintercept = polya_start_position/sampling_rate, color = "#700f25")
    g.line2 <- ggplot2::geom_vline(xintercept = polya_end_position/sampling_rate, color = "#0f3473")
    g.labs <- ggplot2::labs(title= paste0("Read ", readname),
                            x="time [s]",
                            y= "signal [pA]")
    g.moves <- ggplot2::geom_line(ggplot2::aes(y = moves * 150), alpha = 0.3)

  } else if (rescale==FALSE) {
    #plotting raw signal
    squiggle <- ggplot2::ggplot(data = signal_df, ggplot2::aes(x = position)) +
      ggplot2::geom_line(ggplot2::aes(y = signal, color = segment)) + ggplot2::theme_bw() +
      ggplot2::scale_colour_manual(values = c("#089bcc", "#f56042", "#3a414d"))
    g.line <- ggplot2::geom_vline(xintercept = polya_start_position, color = "#700f25")
    g.line2 <- ggplot2::geom_vline(xintercept = polya_end_position, color = "#0f3473")
    g.labs <- ggplot2::labs(title= paste0("Read ", readname),
                            x="position",
                            y= "signal [raw]")
    g.moves <- ggplot2::geom_line(ggplot2::aes(y = moves * 1000), alpha = 0.3)
  }

  if (moves==TRUE) {
    plot_squiggle <- squiggle + g.line + g.line2 + g.labs + g.moves
  }
  else if (moves==FALSE) {
    plot_squiggle <- squiggle + g.line + g.line2 + g.labs
  }

  return(plot_squiggle)

}


#' Draws tail range squiggle for given read.
#'
#' Creates segmented plot of raw/rescaled ONT RNA signal (with or without moves).
#' A standalone function; does not rely on any other preprocessing, depends
#' solely on Nanopolish, Guppy and fast5 input.
#'
#' The output plot includes an entire tail region (orange) and +/- 150 positions
#' flanks of adapter (blue) and transcript body (black) regions. Vertical lines
#' mark the 5' (navy blue) and 3' (red) termini of polyA tail according to the
#' Nanopolish polyA function. In order to maintain readability of the graph
#' (and to avoid plotting high cliffs - e.g. jets of the signal caused
#' by a sudden surge of current in the sensor) the signal is winsorised.
#'
#' Moves may be plotted only for reads basecalled by Guppy basecaller.
#' Otherwise the function will throw an error.
#'
#' @param readname character string. Name of the given read within the
#' analyzed dataset.
#'
#' @param nanopolish character string. Full path of the .tsv file produced
#' by nanopolish polya function.
#'
#' @param sequencing_summary character string. Full path of the .txt file
#' with sequencing summary.
#'
#' @param workspace character string. Full path of the directory to search the
#' basecalled fast5 files in. The Fast5 files have to be multi-fast5 file.
#'
#' @param basecall_group character string ("Basecall_1D_000" is set
#' as a default). Name of the level in the Fast5 file hierarchy from
#' which the data should be extracted.
#'
#' @param moves logical [TRUE/FALSE]. If TRUE, moves would be plotted in
#' the background as vertical bars/gaps (for values 0/1, respectively)
#' and the signal (squiggle) would be plotted in the foreground.
#' Otherwise, only the signal would be plotted. As a default,
#' "FALSE" value is set.
#'
#' @param rescale logical [TRUE/FALSE]. If TRUE, the signal will be rescaled for
#' picoamps (pA) per second (s). If FALSE, raw signal per position will be
#' plotted. As a default, the "FALSE" value is set.
#'
#' @return ggplot2 object with squiggle plot centered on tail range.
#' @export
#'
#' @examples
#' \dontrun{
#'
#' plot <- ninetails::plot_tail_range(
#'   readname = "0226b5df-f9e5-4774-bbee-7719676f2ceb",
#'   nanopolish = system.file('extdata',
#'                            'test_data',
#'                            'nanopolish_output.tsv',
#'                            package = 'ninetails'),
#'   sequencing_summary = system.file('extdata',
#'                                    'test_data',
#'                                    'sequencing_summary.txt',
#'                                    package = 'ninetails'),
#'   workspace = system.file('extdata',
#'                           'test_data',
#'                           'basecalled_fast5',
#'                           package = 'ninetails'),
#'   basecall_group = 'Basecall_1D_000',
#'   moves = TRUE,
#'   rescale = TRUE)
#'
#' print(plot)
#'
#'}
#

plot_tail_range <- function(readname,
                            nanopolish,
                            sequencing_summary,
                            workspace,
                            basecall_group = "Basecall_1D_000",
                            moves=FALSE,
                            rescale=FALSE){

  # variable binding (suppressing R CMD check from throwing an error)
  polya_start <- transcript_start <- adapter_start <- leader_start <- filename <- read_id <- position <- time <- pA <- segment <- NULL


  #Assertions
  if (missing(readname)) {
    stop("Readname [string] is missing. Please provide a valid readname argument.", call. =FALSE)
  }

  if (missing(workspace)) {
    stop("Directory [string] with basecalled fast5s is missing. Please provide a valid workspace argument.", call. =FALSE)
  }
  if (missing(sequencing_summary)) {
    stop("Sequencing summary file [string] is missing. Please provide a valid sequencing_summary argument.", .call = FALSE)
  }

  if (missing(nanopolish)) {
    stop("Nanopolish polya output [string] is missing. Please provide a valid nanopolish argument.", .call = FALSE)
  }



  if (checkmate::test_string(nanopolish)) {
    # if string provided as an argument, read from file
    # handle nanopolish
    assertthat::assert_that(assertive::is_existing_file(nanopolish),
                            msg=paste0("File ",nanopolish," does not exist",sep=""))
    nanopolish <- vroom::vroom(nanopolish, col_select=c(readname,
                                                        polya_start,
                                                        transcript_start,
                                                        adapter_start,
                                                        leader_start),
                               show_col_types = FALSE)
    colnames(nanopolish)[1] <- "read_id" #because there was conflict with the same vars
  }

  #else: make sure that nanopolish is an  object with rows
  assertthat::assert_that(assertive::has_rows(nanopolish),
                          msg = "Empty data frame provided as an input (nanopolish). Please provide valid input")


  nanopolish <- nanopolish[nanopolish$read_id==readname,]
  adapter_start_position <- nanopolish$adapter_start
  leader_start_position <- nanopolish$leader_start
  polya_start_position <- nanopolish$polya_start
  transcript_start_position <-nanopolish$transcript_start
  #define polya end position
  polya_end_position <- transcript_start_position -1


  if (checkmate::test_string(sequencing_summary)) {
    #handle sequencing summary
    assertthat::assert_that(assertive::is_existing_file(sequencing_summary),
                            msg=paste0("File ",sequencing_summary," does not exist",sep=""))
    sequencing_summary <- vroom::vroom(sequencing_summary, col_select = c(filename, read_id), show_col_types = FALSE)
  }

  sequencing_summary <- sequencing_summary[sequencing_summary$read_id==readname,]

  assertthat::assert_that(assertive::has_rows(sequencing_summary),
                          msg = "Empty data frame provided as an input (sequencing_summary). Please provide valid input")

  # Extract data from fast5 file
  fast5_file <- sequencing_summary$filename
  fast5_readname <- paste0("read_",readname) # in fast5 file structure each readname has suffix "read_"
  fast5_file_path <-file.path(workspace, fast5_file) #this is path to browsed fast5 file


  signal <- rhdf5::h5read(file.path(fast5_file_path),paste0(fast5_readname,"/Raw/Signal"))
  signal <- as.vector(signal) # initially signal is stored as an array, I prefer to vectorize it for further manipulations with dframes

  # retrieving sequence, traces & move tables
  BaseCalled_template <- rhdf5::h5read(fast5_file_path,paste0(fast5_readname,"/Analyses/", basecall_group, "/BaseCalled_template"))
  move <- BaseCalled_template$Move #how the basecaller "moves" through the called sequence, and allows for a mapping from basecall to raw data
  move <- as.numeric(move) # change data type as moves are originally stored as raw

  #read parameters stored in channel_id group
  channel_id <- rhdf5::h5readAttributes(fast5_file_path,paste0(fast5_readname,"/channel_id")) # parent dir for attributes (within fast5 file)
  digitisation <- channel_id$digitisation # number of quantisation levels in the analog to digital converter
  digitisation <- as.integer(digitisation)
  offset <- channel_id$offset # analog to digital signal error
  offset <- as.integer(offset)
  range <- channel_id$range # difference between the smallest and greatest values
  range <- as.integer(range)
  sampling_rate <- channel_id$sampling_rate # number of data points collected per second
  sampling_rate <- as.integer(sampling_rate)

  #read parameters (attrs) stored in basecall_1d_template
  basecall_1d_template <- rhdf5::h5readAttributes(fast5_file_path,paste0(fast5_readname,"/Analyses/", basecall_group, "/Summary/basecall_1d_template")) # parent dir for attributes (within fast5)
  stride <- basecall_1d_template$block_stride #  this parameter allows to sample data elements along a dimension
  called_events <- basecall_1d_template$called_events # number of events (nanopore translocations) recorded by device for given read

  # close all handled instances (groups, attrs) of fast5 file
  rhdf5::h5closeAll()

  #winsorize signal (remove cliffs) thanks to this, all signals are plotted without current jets
  signal_q <- stats::quantile(x=signal, probs=c(0.002, 0.998), na.rm=TRUE, type=7)
  minimal_val <- signal_q[1L]
  maximal_val <- signal_q[2L]
  signal[signal<minimal_val] <- minimal_val
  signal[signal>maximal_val] <- maximal_val
  signal <- as.integer(signal)


  # number of events expanded for whole signal vec (this is estimation of signal length, however keep in mind that decimal values are ignored)
  number_of_events <- called_events * stride
  signal_length <- length(signal)

  #handling move data
  moves_sample_wise_vector <- c(rep(move, each=stride), rep(NA, signal_length - number_of_events))

  #creating signal df
  signal_df <- data.frame(position=seq(1,signal_length,1), signal=signal[1:signal_length], moves=moves_sample_wise_vector) # this is signal converted to dframe


  # signal segmentation factor
  #adapter sequence
  signal_df$segment[signal_df$position < polya_start_position] <- "adapter"
  #transcript sequence
  signal_df$segment[signal_df$position >= transcript_start_position] <- "transcript"
  #polya sequence
  signal_df$segment[signal_df$position >= polya_start_position & signal_df$position <= polya_end_position] <- "poly(A)"
  signal_df$segment <- as.factor(signal_df$segment)

  # trim tail region:
  trim_position_upstream <- polya_start_position -150
  trim_position_downstream <- transcript_start_position +150

  signal_df <- signal_df[trim_position_upstream:trim_position_downstream,]

  # plotting squiggle

  if (rescale==TRUE) {
    #additional df cols need for rescaling data
    signal_df <- dplyr::mutate(signal_df, time = position/sampling_rate)
    signal_df <- dplyr::mutate(signal_df, pA = ((signal + offset) * (range/digitisation)))
    #plotting signal rescaled to picoamps per second
    squiggle <- ggplot2::ggplot(data = signal_df, ggplot2::aes(x = time)) +
      ggplot2::geom_line(ggplot2::aes(y = pA, color = segment)) + ggplot2::theme_bw() +
      ggplot2::scale_colour_manual(values = c("#089bcc", "#f56042", "#3a414d"))
    g.line <- ggplot2::geom_vline(xintercept = polya_start_position/sampling_rate, color = "#700f25")
    g.line2 <- ggplot2::geom_vline(xintercept = polya_end_position/sampling_rate, color = "#0f3473")
    g.labs <- ggplot2::labs(title= paste0("Read ", readname),
                            x="time [s]",
                            y= "signal [pA]")
    g.moves <- ggplot2::geom_line(ggplot2::aes(y = moves * 150), alpha = 0.3)

  } else if (rescale==FALSE) {
    #plotting raw signal
    squiggle <- ggplot2::ggplot(data = signal_df, ggplot2::aes(x = position)) +
      ggplot2::geom_line(ggplot2::aes(y = signal, color = segment)) + ggplot2::theme_bw() +
      ggplot2::scale_colour_manual(values = c("#089bcc", "#f56042", "#3a414d"))
    g.line <- ggplot2::geom_vline(xintercept = polya_start_position, color = "#700f25")
    g.line2 <- ggplot2::geom_vline(xintercept = polya_end_position, color = "#0f3473")
    g.labs <- ggplot2::labs(title= paste0("Read ", readname),
                            x="position",
                            y= "signal [raw]")
    g.moves <- ggplot2::geom_line(ggplot2::aes(y = moves * 1000), alpha = 0.3)
  }

  if (moves==TRUE) {
    plot_squiggle <- squiggle + g.line + g.line2 + g.labs + g.moves
  }
  else if (moves==FALSE) {
    plot_squiggle <- squiggle + g.line + g.line2 + g.labs
  }

  return(plot_squiggle)

}

#' Draws a portion of poly(A) tail squiggle (chunk) for given read.
#'
#' This function allows to visualise a single fragment of the poly(A) tail area
#' defined by the fragment name (chunk_name). Intended for use on the output of
#' create_tail_chunk_list_moved function.
#'
#' Currently, draws only the raw signal, without the option to scale
#' to picoamperes [pA].
#'
#' @param chunk_name character string. Name of the given read segment (chunk)
#' within the given tail_chunk_list object.
#'
#' @param tail_chunk_list character string. The list object produced
#' by create_chunk_list function.
#'
#' @return ggplot2 object with squiggle plot depicting given fragment of
#' analyzed poly(A) tail.
#'
#' @export
#'
#' @examples
#'\dontrun{
#'
#'example <- ninetails::plot_tail_chunk(
#'  chunk_name = "5c2386e6-32e9-4e15-a5c7-2831f4750b2b_1",
#'  tail_chunk_list = tcl)
#'
#' print(example)
#'
#'}

plot_tail_chunk <- function(chunk_name,
                            tail_chunk_list) {

  # avoiding variable binding err
  signal_name <- signal <- signal_df <- position <- p <- NULL

  #assertions
  if (missing(tail_chunk_list)) {
    stop("List of tail chunks is missing. Please provide a valid tail_chunk_list argument.", call. =FALSE)
  }

  if (missing(chunk_name)) {
    stop("Chunk_name is missing. Please provide a valid chunk_name argument.", call. =FALSE)
  }

  assertthat::assert_that(assertive::is_list(tail_chunk_list),
                          msg=paste("Given tail_chunk_list object is not a list. Please provide a valid argument."))

  #TODO
  #add assertion checking whether given chunk is present in the tail chunk list or not

  #retrieve actual signal name from chiunk_name
  signal_name <- gsub("\\_.*","",chunk_name)

  #retrieve the signal values from tail_chunk_list
  signal <- tail_chunk_list[[signal_name]][[chunk_name]][[1]]

  #create signal dataframe for plotting
  signal_df <- data.frame(position=seq(1,length(signal),1),signal=signal[1:length(signal)])

  #plot
  plot_squiggle <- ggplot2::ggplot(data = signal_df, ggplot2::aes(x = position)) +
    ggplot2::geom_line(ggplot2::aes(y = signal), color="#3271a8") +
    ggplot2::theme_bw() +
    ggplot2::labs(title=paste0("Read ", chunk_name))

  return(plot_squiggle)
}


#' Creates a visual representation of gramian angular field corresponding to the
#' given poly(A) tail fragment (chunk).
#'
#' The function uses a rainbow palette from grDevices, which makes the matrix
#' more visually pleasing than greyscale (however this is just a visual sugar
#' for human user, as the computer "sees" the data in greyscale
#' (each of 2 dimensions as single-channel matrix).
#'
#' IMPORTANT NOTE!
#' Please keep in mind that the matrices produced by ninetails pipeline are
#' originally two-dimensional arrays (GASF & GADF combined). Each of the
#' dimensions are plotted alltogether (collapsed) as a single depiction.
#' However, they can be splitted, but this requires additional processing steps.
#' For the purpose of ONT signal classification, this combined GASF + GADF
#' approach turned out to be the most suitable, thus the single-dimension
#' extraction is currently not implemented within ninetails plotting functions
#' (which does not mean it would not be).
#'
#' User can control the size of the plot by defining the dimensions within the
#' code chunk in R/RStudio. However, please keep in mind that the ninetails'
#' default built-in model was trained on 100x100 gasfs.
#'
#' @param gaf_name character string. Name of the given read segment (chunk)
#' for which the gaf is meant to be plotted. This is the name of the given gaf
#' within the gaf_list produced by the create_gaf_list function.
#'
#' @param gaf_list A list of gaf matrices organized by the read ID_index.
#' @param save_file logical [TRUE/FALSE]. If TRUE, the gaf plot 100x100 (pixels)
#' would be saved in the current workng directory. If FALSE, the plot would be
#' displayed only in the window. This parameter is set to FALSE by default.
#'
#' @return gramian angular field representing given fragment
#' of nanopore read signal.
#'
#' @export
#'
#' @examples
#' \dontrun{
#'
#'example_gaf <- ninetails::plot_gaf(
#'  gaf_name = "5c2386e6-32e9-4e15-a5c7-2831f4750b2b_1",
#'  gaf_list = gl,
#'  save_file = TRUE)
#'
#'print(example_gaf)
#'
#'}
plot_gaf <- function(gaf_name,
                     gaf_list,
                     save_file=FALSE){

  #avoiding 'no visibe binding to variable' error
  plt <- gaf <- Var2 <- Var1 <- value <- NULL


  #assertions
  if (missing(gaf_name)) {
    stop("Gaf_name is missing. Please provide a valid gaf_name argument.", call. =FALSE)
  }

  if (missing(gaf_list)) {
    stop("List of GAFs is missing. Please provide a valid gaf_list argument.", call. =FALSE)
  }

  assertthat::assert_that(assertive::is_list(gaf_list),
                          msg=paste("Given gaf_list object is not a list. Please provide a valid argument."))
  assertthat::assert_that(gaf_name %in% names(gaf_list),
                          msg = "Given gaf_list does not contain provided gaf_name. Please provide a valid gaf_name argument.")

  #extract gaf of interest
  gaf <- gaf_list[[gaf_name]]
  #reshape the data so the ggplot will accept their format
  gaf <- reshape2::melt(gaf)

  #plot
  plt <- gaf %>% ggplot2::ggplot(ggplot2::aes(Var2, Var1, fill=value)) +
    ggplot2::geom_raster() +
    ggplot2::scale_fill_gradientn(colours = grDevices::rainbow(100), guide="none") +
    ggplot2::scale_y_continuous(expand = c(0, 0)) +
    ggplot2::scale_x_continuous(expand = c(0, 0)) +
    ggplot2::theme(axis.text = ggplot2::element_blank(),
                   axis.ticks = ggplot2::element_blank(),
                   axis.title = ggplot2::element_blank(),
                   panel.background = ggplot2::element_blank(),
                   plot.margin=grid::unit(c(0,0,0,0), "mm")) +
    ggplot2::theme_void()


  if (save_file==TRUE) {
    ggplot2::ggsave(paste0(gaf_name, ".png"), device = "png", width = 100, height = 100, units = "px",bg = "transparent")
  }

  return(plt)

}

#' Creates a visual representation of multiple gramian angular fields
#' based on provided gaf_list (plots all gafs from the given list).
#'
#' The function saves the plots to files with predefined size 100x100 pixels.
#'
#' A feature useful for creating custom data sets for network training.
#' It is recommended to use this feature with caution. Producing multiple graphs
#' from extensive data sets may cause the system to crash.
#'
#' This function plots one-channel (100,100,1) as well as
#' multi-channel gafs (e.g. 100,100,2).
#'
#' IMPORTANT NOTE! In current version, this function plots multi-channel matrices
#' in collapsed manner. If one wants to separate color spaces to GASF/GADF
#' channels or to R,G,B space, this function would not be suitable. The data
#' would require additional processing steps!
#'
#' @param gaf_list A list of gaf matrices organized by the read ID_index.
#'
#' @param num_cores numeric [1]. Number of physical cores to use in processing
#' the data. Do not exceed 1 less than the number of cores at your disposal.
#'
#' @return multiple png files containing gramian angular fields representing
#' given fragment of nanopore read signal.
#'
#' @export
#'
#' @examples
#' \dontrun{
#'
#' ninetails::plot_multiple_gaf(gaf_list = gl, num_cores = 10)
#'
#'}

plot_multiple_gaf <- function(gaf_list,
                              num_cores){
  #avoiding 'no visibe binding to variable' error
  nam <- NULL

  #assertions
  if (missing(gaf_list)) {
    stop("List of GAFs is missing. Please provide a valid gaf_list argument.", call. =FALSE)
  }

  if (missing(num_cores)) {
    stop("Number of declared cores is missing. Please provide a valid num_cores argument.", call. =FALSE)
  }

  assertthat::assert_that(assertive::is_list(gaf_list),
                          msg=paste("Given gaf_list object is not a list. Please provide a valid argument."))
  assertthat::assert_that(assertive::is_numeric(num_cores),
                          msg=paste0("Declared core number must be numeric. Please provide a valid argument."))


  # creating cluster for parallel computing
  my_cluster <- parallel::makeCluster(num_cores)
  on.exit(parallel::stopCluster(my_cluster))

  doSNOW::registerDoSNOW(my_cluster)
  `%dopar%` <- foreach::`%dopar%`
  `%do%` <- foreach::`%do%`

  # this is list of indexes required for parallel computing; the main list is split for chunks
  index_list = split(1:length(names(gaf_list)), ceiling(1:length(names(gaf_list))/100))


  # header for progress bar
  cat(paste('Drawing graphs...', '\n', sep=''))

  # progress bar
  pb <- utils::txtProgressBar(min = 0,
                              max = length(index_list),
                              style = 3,
                              width = 50,
                              char = "=",
                              file = stderr())

  #create empty list for extracted data
  plot_list = list()

  # loop for parallel extraction
  for (indx in 1:length(index_list)){
    plot_list <- c(plot_list, foreach::foreach(nam = names(gaf_list)[index_list[[indx]]]) %dopar% ninetails::plot_gaf(nam,gaf_list,save_file=FALSE))
    utils::setTxtProgressBar(pb, indx)
  }

  #close(pb)

  #label each signal according to corresponding read name to avoid confusion
  gaf_names <- names(gaf_list)
  names(plot_list) <- gaf_names

  #plot all the files
  mapply(ggplot2::ggsave, file=paste0(names(plot_list), ".png"), plot=plot_list, device = "png", width = 100, height = 100, units = "px",bg = "transparent")
}





