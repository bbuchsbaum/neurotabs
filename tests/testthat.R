library(testthat)
library(neurotabs)

old <- options(neurotabs.compute.workers = 1L)
on.exit(options(old), add = TRUE)

test_check("neurotabs")
