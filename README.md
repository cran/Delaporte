# Delaporte

**Delaporte** is an `R` package which provides the probability mass, distribution, quantile, and random variate generator functions for the Delaporte distribution. As the distribution does not have a closed form and requires summations or double summations to calculate values, the functions have been programmed in C++ using the [Rcpp](http://cran.r-project.org/web/packages/Rcpp/index.html) package. In cases where approximations are sufficient, the quantile and random variate generator have the option to use a much faster Poisson-negative binomial estimate as opposed to the full Delaporte double summations.