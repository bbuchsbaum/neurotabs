#include <Rcpp.h>
#include <cmath>
#include <limits>

using namespace Rcpp;

// [[Rcpp::export]]
double cpp_numeric_stat(NumericVector x, std::string op) {
  const R_xlen_t n = x.size();
  if (n == 0) {
    return NA_REAL;
  }

  if (op == "sum") {
    double total = 0.0;
    for (R_xlen_t i = 0; i < n; ++i) {
      total += x[i];
    }
    return total;
  }

  if (op == "mean") {
    double total = 0.0;
    for (R_xlen_t i = 0; i < n; ++i) {
      total += x[i];
    }
    return total / static_cast<double>(n);
  }

  if (op == "l2") {
    double total = 0.0;
    for (R_xlen_t i = 0; i < n; ++i) {
      total += x[i] * x[i];
    }
    return std::sqrt(total);
  }

  if (op == "nnz") {
    double count = 0.0;
    for (R_xlen_t i = 0; i < n; ++i) {
      if (x[i] != 0.0) {
        count += 1.0;
      }
    }
    return count;
  }

  if (op == "min") {
    double current = x[0];
    for (R_xlen_t i = 1; i < n; ++i) {
      if (x[i] < current) {
        current = x[i];
      }
    }
    return current;
  }

  if (op == "max") {
    double current = x[0];
    for (R_xlen_t i = 1; i < n; ++i) {
      if (x[i] > current) {
        current = x[i];
      }
    }
    return current;
  }

  if (op == "sd") {
    if (n < 2) {
      return 0.0;
    }
    double mean = 0.0;
    double m2 = 0.0;
    double count = 0.0;
    for (R_xlen_t i = 0; i < n; ++i) {
      count += 1.0;
      const double delta = x[i] - mean;
      mean += delta / count;
      const double delta2 = x[i] - mean;
      m2 += delta * delta2;
    }
    return std::sqrt(m2 / (count - 1.0));
  }

  stop("unsupported stat op");
}

// [[Rcpp::export]]
NumericVector cpp_matrix_row_stat(NumericMatrix x, std::string op) {
  const R_xlen_t nrow = x.nrow();
  const R_xlen_t ncol = x.ncol();
  NumericVector out(nrow, NA_REAL);

  if (ncol == 0) {
    return out;
  }

  for (R_xlen_t i = 0; i < nrow; ++i) {
    if (op == "sum" || op == "mean" || op == "l2" || op == "nnz") {
      double acc = 0.0;
      for (R_xlen_t j = 0; j < ncol; ++j) {
        const double value = x(i, j);
        if (op == "l2") {
          acc += value * value;
        } else if (op == "nnz") {
          if (value != 0.0) {
            acc += 1.0;
          }
        } else {
          acc += value;
        }
      }
      if (op == "mean") {
        out[i] = acc / static_cast<double>(ncol);
      } else if (op == "l2") {
        out[i] = std::sqrt(acc);
      } else {
        out[i] = acc;
      }
      continue;
    }

    if (op == "min" || op == "max") {
      double current = x(i, 0);
      for (R_xlen_t j = 1; j < ncol; ++j) {
        const double value = x(i, j);
        if (op == "min") {
          if (value < current) {
            current = value;
          }
        } else {
          if (value > current) {
            current = value;
          }
        }
      }
      out[i] = current;
      continue;
    }

    if (op == "sd") {
      if (ncol < 2) {
        out[i] = 0.0;
        continue;
      }
      double mean = 0.0;
      double m2 = 0.0;
      double count = 0.0;
      for (R_xlen_t j = 0; j < ncol; ++j) {
        count += 1.0;
        const double value = x(i, j);
        const double delta = value - mean;
        mean += delta / count;
        const double delta2 = value - mean;
        m2 += delta * delta2;
      }
      out[i] = std::sqrt(m2 / (count - 1.0));
      continue;
    }

    stop("unsupported row stat op");
  }

  return out;
}

// [[Rcpp::export]]
NumericVector cpp_accumulate_sum(NumericVector acc, NumericVector x) {
  if (acc.size() != x.size()) {
    stop("accumulator and input must have the same length");
  }

  const R_xlen_t n = acc.size();
  for (R_xlen_t i = 0; i < n; ++i) {
    acc[i] += x[i];
  }

  return acc;
}

// [[Rcpp::export]]
NumericVector cpp_accumulate_sumsq(NumericVector acc, NumericVector x) {
  if (acc.size() != x.size()) {
    stop("accumulator and input must have the same length");
  }

  const R_xlen_t n = acc.size();
  for (R_xlen_t i = 0; i < n; ++i) {
    acc[i] += x[i] * x[i];
  }

  return acc;
}
