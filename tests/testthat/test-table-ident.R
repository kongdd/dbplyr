test_that("can create table idents", {
  expect_equal(
    new_table_ident(
      table = c("A", "B", "C"),
      schema = "schema"
    ),
    vctrs::new_rcrd(list(
      table = c("A", "B", "C"),
      schema = vctrs::vec_rep("schema", 3),
      catalog = vctrs::vec_rep(NA_character_, 3),
      quoted = vctrs::vec_rep(FALSE, 3),
      alias = vctrs::vec_rep(NA_character_, 3)
    ), class = "dbplyr_table_ident")
  )
})

test_that("is properly vectorised", {
  expect_equal(
    new_table_ident(
      table = c("A", "B"),
      schema = c("schema1", "schema2"),
      catalog = c("cat1", "cat2")
    ),
    vctrs::new_rcrd(list(
      table = c("A", "B"),
      schema = c("schema1", "schema2"),
      catalog = c("cat1", "cat2"),
      quoted = vctrs::vec_rep(FALSE, 2),
      alias = vctrs::vec_rep(NA_character_, 2)
    ), class = "dbplyr_table_ident")
  )

  expect_snapshot(error = TRUE, {
    new_table_ident(table = c("A", "B", "c"), schema = c("schema1", "schema2"))
  })
})

test_that("can't supply table and sql", {
  expect_snapshot(error = TRUE, {
    new_table_ident(schema = "my schema", table = "my table", quoted = TRUE)
  })
})

test_that("must supply table and schema when catalog is used", {
  expect_snapshot(error = TRUE, {
    new_table_ident(table = "my table", catalog = "cat")
    new_table_ident(schema = "schema", catalog = "cat")
  })

  # also works when schema is a vector
  expect_snapshot(error = TRUE, {
    new_table_ident(table = "my table", schema = c("my schema", NA), catalog = "cat")
  })
})

test_that("can't coerce or cast to character", {
  table <- new_table_ident(table = "table")
  expect_snapshot(error = TRUE, {
    c(table, "character")
    as.character(table)
  })
})

test_that("can print", {
  expect_snapshot({
    new_table_ident(table = "table")
    new_table_ident(schema = "schema", table = "table")
    new_table_ident(catalog = "catalog", schema = "schema", table = "table")
    new_table_ident(table = "`my schema`.`my table`", quoted = TRUE)
  })

  # is correctly vectorised
  expect_snapshot(
    new_table_ident(
      table   = c("`my schema`.`my table`", "table1",  "table2",   "table3"),
      schema  = c(                      NA,       NA, "schema2",  "schema3"),
      catalog = c(                      NA,       NA,        NA, "catalog3"),
      quoted  = c(                    TRUE,    FALSE,     FALSE,      FALSE)
    )
  )
})

test_that("as_table_ident works", {
  expect_equal(
    as_table_ident("table"),
    new_table_ident(table = "table")
  )

  expect_equal(
    as_table_ident(ident("table")),
    new_table_ident(table = "table")
  )

  expect_equal(
    as_table_ident(in_schema("schema", "table")),
    new_table_ident(schema = "schema", table = "table")
  )

  expect_equal(
    as_table_ident(in_catalog("catalog", "schema", "table")),
    new_table_ident(catalog = "catalog", schema = "schema", table = "table")
  )

  expect_equal(
    as_table_ident(DBI::Id(catalog = "catalog", schema = "schema", table = "table")),
    new_table_ident(catalog = "catalog", schema = "schema", table = "table")
  )

  table <- new_table_ident(table = "table")
  expect_equal(
    as_table_ident(table),
    table
  )

  withr::local_options(rlib_message_verbosity = "verbose")
  expect_snapshot({
    expect_equal(
      as_table_ident(ident_q("my schema.my table")),
      new_table_ident(table = "my schema.my table", quoted = TRUE)
    )
    expect_equal(
      as_table_ident(sql("my schema.my table")),
      new_table_ident(table = "my schema.my table", quoted = TRUE)
    )
  })
})

test_that("escaped as needed", {
  con <- simulate_dbi()
  out <- c(
    as_table_ident(ident("table1")),
    as_table_ident(in_schema("schema2", "table2")),
    as_table_ident(in_catalog("catalog3", "schema3", "table3"))
  )

  expect_equal(
    escape(out, collapse = NULL, con = simulate_dbi()),
    sql(
      "`table1`",
      "`schema2`.`table2`",
      "`catalog3`.`schema3`.`table3`"
    )
  )
})
