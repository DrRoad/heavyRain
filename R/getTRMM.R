#' Download TRMM 3B42 Data
#'
#' @description
#' Download TRMM 3B42 version 7 daily (NetCDF) or 3-hourly (HDF) files for a
#' given time span from the
#' \href{https://disc2.gesdisc.eosdis.nasa.gov/data/TRMM_L3/}{NASA FTP servers}.
#'
#' @param begin,end Start and end date as \code{Date} or \code{character}.
#' @param type \code{character}. Temporal resolution of downloaded TRMM data.
#' Currently available options are \code{"daily"} (default) and
#' \code{"3-hourly"}.
#' @param dsn \code{character}. Download folder, defaults to the current working
#' directory.
#' @param xml \code{logical}, defaults to \code{FALSE}. If \code{TRUE}, .xml
#' files associated with each .nc4 file are also downloaded to 'dsn'.
#' @param overwrite \code{logical}, defaults to \code{FALSE}. Determines whether
#' existing files are overwritten.
#' @param quiet \code{logical}. If \code{TRUE} (default), possible status
#' messages and progress bar are suppressed, see \code{\link{download.file}}.
#' @param cores \code{integer}. Number of cores for parallel processing. Note
#' that this takes only effect if a sufficiently fast internet connection is
#' available.
#' @param ... In case 'begin' and/or 'end' are \code{character} objects,
#' additional arguments passed to \code{\link{as.Date}}.
#'
#' @return
#' If \code{xml = FALSE} (default), a \code{character} vector of local file
#' paths. Else a \code{list} of file paths with each entry corresponding to a
#' single date.
#'
#' @author
#' Florian Detsch
#'
#' @seealso
#' \code{\link{download.file}}.
#'
#' @references
#' MacRitchie K (2015) README Document for the Tropical Rainfall Measurement
#' Mission (TRMM). Available online:
#' \url{https://disc2.gesdisc.eosdis.nasa.gov/data/TRMM_L3/TRMM_3B43/doc/README.TRMM_V7.pdf}
#' (2018-10-01).
#'
#' @examples
#' \dontrun{
#' ## download TRMM 3B42 daily data from Jan 1 to Jan 5, 2015
#' getTRMM(begin = "2015-01-01", end = "2015-01-05")
#'
#' ## same for 3-hourly data
#' getTRMM(begin = "2015-01-01", end = "2015-01-05", type = "3-hourly")
#' }
#'
#' @export getTRMM
#' @aliases getTRMM
getTRMM <- function(begin, end, type = c("daily", "3-hourly"),
                         dsn = ".", xml = FALSE, overwrite = FALSE,
                         quiet = TRUE, cores = 1L, ...) {

  ## time frame
  if (missing(begin)) begin <- as.Date("1998-01-01")
  if (missing(end)) end <- Sys.Date()

  ## transform 'begin' and 'end' to 'Date' object if necessary
  if (!inherits(begin, "Date"))
    begin <- as.Date(begin, ...)

  if (!inherits(end, "Date"))
    end <- as.Date(end, ...)

  ## create online and offline target files
  onl <- getTRMMFiles(begin, end, type, xml)
  ofl <- paste(dsn, basename(onl), sep = "/")

  ## parallelization
  cl <- parallel::makePSOCKcluster(cores)
  parallel::clusterExport(cl, c("onl", "ofl", "overwrite", "quiet"),
                          envir = environment())
  on.exit(parallel::stopCluster(cl))

  ## download
  hdf <- parallel::parLapply(cl, 1:length(onl), function(i) {

    # if target file exists and overwrite is disabled, return local file
    ofl1 <- ofl[i]; ofl2 <- gsub("7.HDF$", "7A.HDF", ofl[i])
    if (any(file.exists(ofl1, ofl2)) & !overwrite)
      return(c(ofl1, ofl2)[which(file.exists(ofl1, ofl2))])

    # else try to download version-7
    if (!file.exists(ofl[i]) | overwrite)
      jnk1 <- try(utils::download.file(onl[i], ofl1, method = "wget",
                                       mode = "wb", quiet = quiet),
                  silent = TRUE)

    # if download of version-7 failed, try version-7a
    if (inherits(jnk1, "try-error")) {
      file.remove(ofl[i])
      jnk2 <- try(utils::download.file(gsub("7.HDF$", "7A.HDF", onl[i]), ofl2,
                                       method = "wget", mode = "wb", quiet = quiet),
                  silent = TRUE)
    }

    # if version-7 was found
    if (!inherits(jnk1, "try-error")) {
      return(ofl1)
    # else if version-7a was found
    } else if (inherits(jnk1, "try-error") & exists("jnk2")) {
      if (!inherits(jnk2, "try-error")) {
        return(ofl2)
      } else {
        return(invisible())
      }
    # else throw warning
    } else {
      warning("Couldn't find file ", onl[i], " (or *7A.HDF). Moving on to next file ...\n")
      return(invisible())
    }
  })

  if (!xml)
    return(unlist(hdf))
  else
    return(hdf)
}


### helper function to create TRMM daily or 3-hourly filenames -----

getTRMMFiles <- function(begin, end, type = c("daily", "3-hourly"),
                         xml = FALSE) {

  ## trmm ftp server
  ftp <- serverPath("trmm")

  ## daily product
  if (type[1] == "daily") {

    # online filepath to daily files
    ftp <- paste0(ftp, "TRMM_3B42_Daily.7")

    # create target filenames
    sqc <- seq(begin, end, "day")

    onl <- strftime(sqc, "%Y/%m/3B42_Daily.%Y%m%d.7.nc4")
    onl <- paste(ftp, onl, sep = "/")
    if (xml) onl <- sort(c(onl, paste0(onl, ".xml")))

  ## 3-hourly product
  } else if (type[1] == "3-hourly") {

    # online filepath to 3-hourly files
    ftp <- paste0(ftp, "TRMM_3B42.7/")

    # create target folder structure
    begin <- as.POSIXct(paste(begin, "00:00:00"))
    end <- as.POSIXct(paste(end, "21:00:00"))
    sqc <- seq(begin, end, "3 hours")

    ftp <- paste0(ftp, strftime(sqc, "%Y/%j"))

    ## create target filenames
    sqc <- sqc + 3 * 60 * 60

    # vrs <- ifelse(as.Date(sqc) >= as.Date("2000-01-01") &
    #                 as.Date(sqc) <= as.Date("2010-10-01"), "7A", "7")
    #
    # onl <- do.call("c", lapply(1:length(sqc), function(i) {
    #   paste0(ftp, strftime(sqc[i], paste0("/3B42.%Y%m%d.%H.", vrs[i], ".HDF")))
    # }))

    onl <- paste0(ftp, strftime(sqc, "/3B42.%Y%m%d.%H.7.HDF"))

    if (xml) onl <- sort(c(onl, paste0(onl, ".xml")))

  ## product not available
  } else {
    stop("Specified product not available, see ?getTRMM for available options.\n")
  }

  return(onl)
}
