#' Escape/quote a string.
#'
#' `escape()` requires you to provide a database connection to control the
#' details of escaping. `escape_ansi()` uses the SQL 92 ANSI standard.
#'
#' @param x An object to escape. Existing sql vectors will be left as is,
#'   character vectors are escaped with single quotes, numeric vectors have
#'   trailing `.0` added if they're whole numbers, identifiers are
#'   escaped with double quotes.
#' @param parens,collapse Controls behaviour when multiple values are supplied.
#'   `parens` should be a logical flag, or if `NA`, will wrap in
#'   parens if length > 1.
#'
#'   Default behaviour: lists are always wrapped in parens and separated by
#'   commas, identifiers are separated by commas and never wrapped,
#'   atomic vectors are separated by spaces and wrapped in parens if needed.
#' @param con Database connection.
#' @rdname escape
#' @export
#' @examples
#' # Doubles vs. integers
#' escape_ansi(1:5)
#' escape_ansi(c(1, 5.4))
#'
#' # String vs known sql vs. sql identifier
#' escape_ansi("X")
#' escape_ansi(sql("X"))
#' escape_ansi(ident("X"))
#'
#' # Escaping is idempotent
#' escape_ansi("X")
#' escape_ansi(escape_ansi("X"))
#' escape_ansi(escape_ansi(escape_ansi("X")))
escape <- function(x, parens = NA, collapse = " ", con = NULL) {
  check_con(con)

  UseMethod("escape")
}

#' @export
#' @rdname escape
escape_ansi <- function(x, parens = NA, collapse = "") {
  escape(x, parens = parens, collapse = collapse, con = simulate_dbi())
}

#' @export
escape.ident <- function(x, parens = FALSE, collapse = ", ", con = NULL) {
  y <- sql_escape_ident(con, x)
  sql_vector(names_to_as(y, names2(x), con = con), parens, collapse, con = con)
}

#' @export
escape.dbplyr_schema <- function(x, parens = FALSE, collapse = ", ", con = NULL) {
  sql_vector(as.sql(x, con = con), parens, collapse, con = con)
}

#' @export
escape.dbplyr_catalog <- function(x, parens = FALSE, collapse = ", ", con = NULL) {
  sql_vector(as.sql(x, con = con), parens, collapse, con = con)
}

#' @export
escape.logical <- function(x, parens = NA, collapse = ", ", con = NULL) {
  sql_vector(sql_escape_logical(con, x), parens, collapse, con = con)
}

#' @export
escape.factor <- function(x, parens = NA, collapse = ", ", con = NULL) {
  x <- as.character(x)
  escape.character(x, parens = parens, collapse = collapse, con = con)
}

#' @export
escape.Date <- function(x, parens = NA, collapse = ", ", con = NULL) {
  sql_vector(sql_escape_date(con, x), parens, collapse, con = con)
}

#' @export
escape.POSIXt <- function(x, parens = NA, collapse = ", ", con = NULL) {
  sql_vector(sql_escape_datetime(con, x), parens, collapse, con = con)
}

#' @export
escape.character <- function(x, parens = NA, collapse = ", ", con = NULL) {
  sql_vector(sql_escape_string(con, x), parens, collapse, con = con)
}

#' @export
escape.double <- function(x, parens = NA, collapse = ", ", con = NULL) {
  out <- ifelse(is_whole_number(x), sprintf("%.1f", x), as.character(x))

  # Special values
  out[is.na(x)] <- "NULL"
  inf <- is.infinite(x)
  out[inf & x > 0] <- "'Infinity'"
  out[inf & x < 0] <- "'-Infinity'"

  sql_vector(out, parens, collapse, con = con)
}

is_whole_number <- function(x) {
  trunc(x) == x
}

#' @export
escape.integer <- function(x, parens = NA, collapse = ", ", con = NULL) {
  x[is.na(x)] <- "NULL"
  sql_vector(x, parens, collapse, con = con)
}

#' @export
escape.integer64 <- function(x, parens = NA, collapse = ", ", con = NULL) {
  x <- as.character(x)
  x[is.na(x)] <- "NULL"
  sql_vector(x, parens, collapse, con = con)
}

#' @export
escape.blob <- function(x, parens = NA, collapse = ", ", con = NULL) {
  pieces <- vapply(x, sql_escape_raw, character(1), con = con)
  sql_vector(pieces, isTRUE(parens) || length(pieces) > 1, collapse, con = con)
}

#' @export
escape.NULL <- function(x, parens = NA, collapse = " ", con = NULL) {
  sql("NULL")
}

#' @export
escape.sql <- function(x, parens = NULL, collapse = NULL, con = NULL) {
  sql_vector(x, isTRUE(parens), collapse, con = con)
}

#' @export
escape.list <- function(x, parens = TRUE, collapse = ", ", con = NULL) {
  pieces <- vapply(x, escape, character(1), con = con)
  sql_vector(pieces, parens, collapse, con = con)
}

#' @export
escape.data.frame <- function(x, parens = TRUE, collapse = ", ", con = NULL) {
  error_embed("a data.frame", "df$x")
}

#' @export
escape.reactivevalues <- function(x, parens = TRUE, collapse = ", ", con = NULL) {
  error_embed("shiny inputs", "input$x")
}

# Also used in default_ops() for reactives
error_embed <- function(type, expr) {
  cli_abort(c(
    "Cannot translate {type} to SQL.",
    `i` = "Do you want to force evaluation in R with (e.g.) `!!{expr}` or `local({expr})`?"
  ), call = NULL)
}

#' @export
#' @rdname escape
sql_vector <- function(x, parens = NA, collapse = " ", con = NULL) {
  check_con(con)

  if (length(x) == 0) {
    if (!is.null(collapse)) {
      return(if (isTRUE(parens)) sql("()") else sql(""))
    } else {
      return(sql())
    }
  }

  if (is.na(parens)) {
    parens <- length(x) > 1L
  }

  x <- names_to_as(x, con = con)
  x <- paste(x, collapse = collapse)
  if (parens) x <- paste0("(", x, ")")
  sql(x)
}

names_to_as <- function(x, names = names2(x), con = NULL) {
  if (length(x) == 0) {
    return(character())
  }

  names_esc <- sql_escape_ident(con, names)
  as_sql <- style_kw(" AS ")
  as <- ifelse(names == "" | names_esc == x, "", paste0(as_sql, names_esc))

  paste0(x, as)
}

#' Helper function for quoting sql elements.
#'
#' If the quote character is present in the string, it will be doubled.
#' `NA`s will be replaced with NULL.
#'
#' @param x Character vector to escape.
#' @param quote Single quoting character.
#' @export
#' @keywords internal
#' @examples
#' sql_quote("abc", "'")
#' sql_quote("I've had a good day", "'")
#' sql_quote(c("abc", NA), "'")
sql_quote <- function(x, quote) {
  if (length(x) == 0) {
    return(x)
  }

  y <- gsub(quote, paste0(quote, quote), x, fixed = TRUE)
  y <- paste0(quote, y, quote)
  y[is.na(x)] <- "NULL"
  names(y) <- names(x)

  y
}
