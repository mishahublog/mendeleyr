#' Create, Load and Save client_id and client_secret
#' @param client_id The client id given by Mendeley when you create an app at http://dev.mendeley.com/myapps.html
#' @param client_secret The client secret given by Mendeley when you create an app
#' @param where File name where mendeleyr will store the client_id and client_secret
#' @param try_env Try loading parameters from OS environment variables `MENDELEY_CLIENT_ID` and `MENDELEY_CLIENT_SECRET`
#' @name mendeley_conf
NULL


#' @rdname mendeley_conf
#' @export
mdl_conf_new <- function() {
  stop("mdl_conf_save requires the client_id and client_secret.\n",
       "You can obtain these registering an app at Mendeley at http://dev.mendeley.com/myapps.html.\n",
       "Please use http://localhost:1410/ as 'Redirect URL'\n",
       "Then you can use:\n",
       'mdl_conf_save(client_id = "given-by-mendeley", client_secret = "given-by-mendeley")\n')
}

#' @rdname mendeley_conf
#' @export
mdl_conf_save <- function(client_id, client_secret, where = ".mendeley_conf.json") {
  if (missing(client_id) || missing(client_secret)) {
  }
  cfg <- jsonlite::toJSON(list(client_id = client_id,
                               client_secret = client_secret))
  write(cfg, file = where)
  message("Your client_id and client_secret have been stored at '",
          file.path(where), "'.\n", "Do not publish your mendeley secrets.")
}

get_conf_environment <- function() {
  client_id <- Sys.getenv("MENDELEY_CLIENT_ID", unset = NA)
  client_secret <- Sys.getenv("MENDELEY_CLIENT_SECRET", unset = NA)
  if (is.na(client_id) || is.na(client_secret)) {
    return(NULL)
  } else {
    return(list(client_id = client_id, client_secret = client_secret))
  }
}


#' @rdname mendeley_conf
#' @export
mdl_conf_load <- function(where = ".mendeley_conf.json", try_env = TRUE) {
  if (isTRUE(try_env)) {
    mendeley_conf <- get_conf_environment()
    if (!is.null(mendeley_conf)) {
      return(mendeley_conf)
    }
  }
  if (!file.exists(where)) {
    stop("Mendeley client_id and client_secret not found in '", where, "'.\n",
         "Please obtain them with mdl_conf_new() and save them with mdl_conf_save()")
  }
  jsonlite::fromJSON(where)
}

#' Obtains a Mendeley Token valid for the current session.
#'
#' The first time you get the token you will need to authorise your application
#' (mendeleyr) access to your account.
#' @param mendeley_conf a list with two items: `client_id` and `client_secret`.
#'  If it is a file path to a json file, it will be loaded with [mdl_conf_load()]
#' @examples
#' \dontrun{
#'  # loads secret from ".mendeley_conf.json" in current directory:
#' token <- mdl_token()
#' # loads secret from "secret.json" in current directory
#' token <- mdl_token("secret.json")
#' # Loads secret from code (not recommended, as it may be accidentally redistributed)
#' token <- mdl_token(list(client_id = "given-by-mendeley", client_secret = "given-by-mendeley"))
#'
#' }
#' @export
mdl_token <- function(mendeley_conf) {
  if (missing(mendeley_conf)) {
      mendeley_conf <- mdl_conf_load()
  } else if (is.character(mendeley_conf) &&
             length(mendeley_conf) == 1 &&
             file.exists(mendeley_conf)) {
    mendeley_conf <- mdl_conf_load(mendeley_conf)
  } else if (!is.list(mendeley_conf)) {
    stop("mdl_token has an invalid mendeley_conf")
  }

  # 1. OAuth settings for mendeley:
  mendeley_oauth <- httr::oauth_endpoint(
    authorize = "https://api.mendeley.com/oauth/authorize",
    access =    "https://api.mendeley.com/oauth/token"
  )

  app <- httr::oauth_app("my_script", mendeley_conf$client_id,
                         mendeley_conf$client_secret)

  # 3. Get OAuth credentials
  token <- httr::oauth2.0_token(mendeley_oauth, app,
                                scope = "all",
                                use_oob = FALSE,
                                use_basic_auth = TRUE)
  token
}

mdl_next_page <- function(response_headers) {
  if (!"link" %in% names(response_headers)) {
    return(NULL)
  }
  links <- which(names(response_headers) == "link")
  all_next <- grep(pattern = 'rel="next"$', x = response_headers[links])
  if (length(all_next) == 0) {
    return(NULL)
  }
  if (length(all_next) > 1) {
    stop("Many next links")
  }
  next_link <- response_headers[[links[all_next[1]]]]
  next_url <- gsub(pattern = "^<(.*)>$", replacement = "\\1",
                   x = strsplit(next_link, ";", fixed = TRUE)[[1]][1])
  return(next_url)
}

mdl_get_all_pages <- function(url, ...) {
  all_pages <- list()
  while (!is.null(url)) {
    doc_rsp <- httr::GET(url, ...)
    stopifnot(doc_rsp$status_code == 200)
    all_pages <- c(
      all_pages,
      jsonlite::fromJSON(rawToChar(httr::content(doc_rsp)),
                         simplifyVector = FALSE)
    )
    url <- mdl_next_page(httr::headers(doc_rsp))
  }
  return(all_pages)
}

# I don't want force the use of dplyr and I need to save list columns
my_bind_rows <- function(x) {
  # We need to specify list columns...
  y <- lapply(
    x,
    function(row) {
      for (i in seq_len(length(row))) {
        if (class(row[[i]]) == "list") {
          row[[i]] <- list(row[[i]])
        }
      }
      return(row)
    })

  if (requireNamespace("dplyr", quietly = TRUE)) {
    as.data.frame(dplyr::bind_rows(y))
  } else {
    do.call(rbind, lapply(y, function(z) as.data.frame(z, stringsAsFactors = FALSE)))
  }
}

#' Gets all the group information
#' @inheritParams mdl_common_params
#' @export
mdl_groups <- function(token) {
  grps <- mdl_get_all_pages("https://api.mendeley.com/groups", token)
  my_bind_rows(grps)
}

get_folder_id <- function(token, folder_name, folder_id, group_id = NULL) {
  if (!is.null(folder_id)) {
    if (!is.null(folder_name)) {
      stop("folder_name and folder_id can't be not null at the same time")
    } else {
      return(folder_id)
    }
  }
  # Group ID is NULL
  if (!is.null(folder_name)) {
    all_folders <- mdl_folders(token, group_id = group_id)
    matched_folders <- all_folders$name == folder_name
    if (sum(matched_folders) == 0) {
      stop("No folder found with name '", folder_name, "'")
    }
    if (sum(matched_folders) > 1) {
      # Is this even possible?
      stop("More than one folder found with name '", folder_name, "'")
    }
    return(all_folders$id[matched_folders])
  }
  return(NULL)
}

get_group_id <- function(token, group_name, group_id) {
  if (!is.null(group_id)) {
    if (!is.null(group_name)) {
      stop("group_name and group_id can't be not null at the same time")
    } else {
      return(group_id)
    }
  }
  # Group ID is NULL
  if (!is.null(group_name)) {
    all_groups <- mdl_groups(token)
    matched_groups <- all_groups$name == group_name
    if (sum(matched_groups) == 0) {
      stop("No group found with name '", group_name, "'")
    }
    if (sum(matched_groups) > 1) {
      # Is this even possible?
      stop("More than one group found with name '", group_name, "'")
    }
    return(all_groups$id[matched_groups])
  }
  return(NULL)
}

#' mdl Common Parameters
#'
#' These are parameters common to several mendeleyr functions
#' @name mdl_common_params
#' @param token A Token given by [mdl_token()] that provides access to your account.
#' @param document_id One or more document IDs. Get the document IDs with [mdl_documents()]
#' @param group_name A group name. Read group IDs through [mdl_groups()]
#' @param group_id A group ID. Read group IDs through [mdl_groups()]
#' @param folder_name A folder name. Get folder names with [mdl_folders()].
#' @param folder_id A folder ID. Get folder names with [mdl_folders()].
NULL

#' Retrieve all the Mendeley folders
#' @inheritParams mdl_common_params
#' @export
mdl_folders <- function(token, group_name = NULL, group_id = NULL) {
  group_id <- get_group_id(token, group_name, group_id)
  url <- form_url("https://api.mendeley.com/folders/", list(group_id = group_id))
  my_bind_rows(
    mdl_get_all_pages(url,
                      token,
                      httr::accept('application/vnd.mendeley-folder.1+json')))
}

#' Get the Document IDs from a given folder_id
#' @inheritParams mdl_common_params
#' @export
mdl_documents <- function(token, folder_name = NULL, folder_id = NULL,
                          group_name = NULL, group_id = NULL) {
  group_id <- get_group_id(token, group_name, group_id)
  folder_id <- get_folder_id(token, folder_name, folder_id, group_id = group_id)
  if (!is.null(folder_id)) {
    url <- paste0("https://api.mendeley.com/folders/", folder_id, "/documents")
  } else {
    url <- paste0("https://api.mendeley.com/documents")
  }
  url <- form_url(url, list(group_id = group_id))

  my_bind_rows(
    mdl_get_all_pages(url,
                      token,
                      httr::accept("application/vnd.mendeley-document.1+json")))
}

#' Download a file
#' @inheritParams mdl_common_params
#' @param file_row A row from [mdl_files()] with the file we want to download
#' @param destfile The path where we want to save destfile, by default keeps
#'                 the original file name in the current working directory
#' @export
mdl_download_file <- function(token, file_row, destfile = NULL) {
  if (is.null(destfile)) {
    outdir <- getwd()
    file_name <- tools::file_path_sans_ext(file_row$file_name)
    file_ext <- tools::file_ext(file_row$file_name)
    destfile <- file.path(outdir, paste0(file_name, ".", file_ext))
    i <- 0
    while (file.exists(destfile)) {
      i <- i + 1
      destfile <- file.path(outdir, paste0(file_name, "-" , i,  ".", file_ext))
    }
  }
  url <- paste0("https://api.mendeley.com/files/", file_row$id)
  result_1 <- httr::GET(url, token)
  curl::curl_download(result_1$url, destfile)
  return(destfile)
}

mdl_docid_as_bibtex_one <- function(token, document_id) {
  url <- form_url(paste0("https://api.mendeley.com/documents/",
                         curl::curl_escape(document_id)),
                  list(view = "bib"))
  doc_rsp <- httr::GET(url,
                       token,
                       httr::accept('application/x-bibtex'))
  stopifnot(doc_rsp$status_code == 200)
  rawToChar(httr::content(doc_rsp))
}

#' Get a document ID as bibtex
#' @inheritParams mdl_common_params
#' @export
mdl_docid_as_bibtex <- function(token, document_id) {
  bibtex <- lapply(document_id,
                   function(document) {
                     mdl_docid_as_bibtex_one(token, document)
                   })
  do.call(paste, c(bibtex, list(sep = "\n\n")))
}

#' Creates a bib file from a Mendeley folder or group
#' @inheritParams mdl_common_params
#' @param bibfile "*.bib" file to write the documents from folder_name
#' @export
mdl_to_bibtex <- function(token, folder_name = NULL, folder_id = NULL,
                          group_name = NULL, group_id = NULL,
                          bibfile = NULL) {
  if (is.null(bibfile)) {
    bibfile <- paste0(folder_name, ".bib")
  }
  group_id <- get_group_id(token, group_name, group_id)
  folder_id <- get_folder_id(token, folder_name, folder_id, group_id = group_id)

  all_documents <- mdl_documents(token, folder_id = folder_id, group_id = group_id)
  bibtex <- mdl_docid_as_bibtex(token, all_documents$id)

  write(bibtex, file = bibfile)
  return()
}

form_url <- function(url, params) {
  include_params <- !vapply(params, is.null, logical(1))
  param_url <- paste(curl::curl_escape(names(params[include_params])),
                     curl::curl_escape(params[include_params]),
                     collapse = "&", sep = "=")
  if (nchar(param_url) == 0) {
    url
  } else {
    paste0(url, "?", param_url)
  }
}

#' Retrieve the list of files attached to documents or groups
#' @inheritParams mdl_common_params
#' @export
mdl_files <- function(token, document_id = NULL, group_name = NULL, group_id = NULL) {
  group_id <- get_group_id(token, group_name, group_id)
  url <- form_url("https://api.mendeley.com/files",
                  list(document_id = document_id,
                       group_id = group_id, view = "client"))
  all_entries_list <- mdl_get_all_pages(
    url,
    token,
    httr::accept('application/vnd.mendeley-file.1+json'),
    httr::content_type('application/vnd.mendeley-file.1+json')
  )
  all_entries <- my_bind_rows(lapply(all_entries_list, my_bind_rows))
  return(all_entries)
}

#' Find documents with duplicated files
#'
#' If a two documents have the same file, we consider that one of them is
#' duplicated. It's better to review manually the entries.
#' @inheritParams mdl_common_params
#' @export
#' @examples
#' \dontrun{
#' token <- mdl_token()
#' docs <- mdl_docs_with_common_files(token, group_name = "mygroup")
#' View(docs$remove)
#' mdl_delete_document(token, docs$remove$document_id)
#' }
mdl_docs_with_common_files <- function(token, group_name = NULL, group_id = NULL) {
  group_id <- get_group_id(token, group_name, group_id)
  all_entries <- mdl_files(token, group_id = group_id)
  dupl_rows <- which(duplicated(all_entries$filehash))
  # If a document has two times the same file (that would be inconsistent,
  # but not the purpose of this tool) the document is not duplicated
  false_positive <- which(duplicated(paste(all_entries$document_id,
                                           all_entries$filehash, sep = "_")))
  dupl_rows <- setdiff(dupl_rows, false_positive)

  keep_rows <- setdiff(seq_len(nrow(all_entries)), dupl_rows)
  all_entries_remove <- all_entries[dupl_rows, , drop = FALSE]
  all_entries_keep <- all_entries[keep_rows, , drop = FALSE]
  list(all = all_entries, keep = all_entries_keep, remove = all_entries_remove)
}

#' Delete a Mendeley document
#' @inheritParams mdl_common_params
#' @export
mdl_delete_document_one <- function(token, document_id) {
  result_1 <- httr::DELETE(paste0("https://api.mendeley.com/documents/",
                                  curl::curl_escape(document_id)), token)
  stopifnot(result_1$status_code == 204)
}

#' Delete one or more documents
#' @inheritParams mdl_common_params
#' @param show_progress logical value to show a progress bar
#' @export
mdl_delete_document <- function(token, document_id, show_progress = interactive()) {
  if (show_progress && length(document_id) > 5) {
    pb <- utils::txtProgressBar(min = 0, max = length(document_id), style = 3)
  } else {
    pb <- NULL
  }
  for (i in seq_len(length(document_id))) {
    mdl_delete_document_one(token, document_id[i])
    if (!is.null(pb)) {
      utils::setTxtProgressBar(pb, i)
    }
  }
  if (!is.null(pb)) {
    close(pb)
  }
}
