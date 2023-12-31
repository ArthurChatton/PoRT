#########################
####
#### Code for the PoRT (Positivity Regression Trees) algorithm 
#### It is an updated and still in developpement version of the port() function implemented in the R package RISCA.
#### Please cite as Danielan et al. (2023) Identifying in sample positivity violations using regression trees: The PoRT algorithm. JOurnal of Causal Inference
#### MIT license, authors: Arthur Chatton (Université de Montréal) and Gabriel Danelian.
#### The main function is port(). Other functions are internal functions needed called in port().
#### If you face an issue, please send a mail at: arthur.chatton@umontreal.ca
####
#########################


library(rpart)
library(rpart.plot)

#' Violation definition
#'
#' Produce a row of result from a problematic subgroup for the user output (table of results).
#'
#' @param subgrp the subgroup produced in port()
#' @param var Variables names defining the subgroup
#' @param type_var Type of the variable (continuous or categorical)
#' @param data Dataset
#' @param pruning Boolean, should we remove subgroup like >30 & <40? 
#' @param type_expo Type of the exposure (binary, continuous, or categorical)
#' @param mediation Boolean, are we in mediation analysis? Only for table labeling
#' @param beta Beta hyperparameter
#' @param group Column name of the exposure
#'
#' @return Table with the violations (subgroup name | exposure probability | exposure level | subgroup size (N) | subgroup size (%))
#'
#' @examples
define_cutoff <- function(subgrp, var, type_var, data, pruning, type_expo="b", mediation=FALSE, beta, group){ 
  n <- subgrp$n[nrow(subgrp)]
  pourcent <- round(n/subgrp$n[1], digits = 3) * 100
  if(type_expo!="b"){
    all_prob <- subgrp$proba[nrow(subgrp),]
    pb_prob <- which(all_prob<=beta | all_prob>=(1-beta))
    proba <- round(all_prob[pb_prob], digits = 3) |> setNames(nm=NULL)
    treat <- levels(data[,group])[pb_prob]
  }else{
    proba <- round(subgrp$proba[nrow(subgrp)], digits = 3) 
    treat <- ifelse(proba >= 0.5, "unexposed", "exposed")
    proba <- ifelse(proba >= 0.5, 1 - proba, proba)
  }
  newcut <- subgrp
  
  for (v in var) {
    if (type_var[var == v] == "continuous") {
      imcs <- newcut$var2[grepl(v, newcut$var2, fixed = TRUE)]
      loc_imcs <- which(subgrp$var2 %in% imcs)
      imcs <- sapply(imcs, function(i) gsub(v, "", i))
      imcs_sup <- imcs[grepl("<", imcs)]
      loc_sup <- loc_imcs[grepl("<", imcs)]
      imcs_inf <- imcs[grepl(">", imcs)]
      loc_inf <- loc_imcs[grepl(">", imcs)]
      if (pruning) {
        if (length(imcs_sup) > 0 && length(imcs_inf) > 
            0) {
          newcut <- NULL
          return(list(subgrp = newcut, table=data.frame()))
        }
      }
      imcs_sup <- as.numeric(vapply(imcs_sup, function(i) substr(i, start = 3, stop = nchar(i)), FUN.VALUE = character(1)))
      imcs_inf <- as.numeric(vapply(imcs_inf, function(i) substr(i, start = 3, stop = nchar(i)), FUN.VALUE = character(1)))
      if (length(imcs_sup) > 1 || length(imcs_inf) > 
          1) {
        imc_sup <- ifelse(length(imcs_sup) > 0, min(imcs_sup), imcs_sup)
        imc_inf <- ifelse(length(imcs_inf) > 0, max(imcs_inf), imcs_inf)
        keep <- c(loc_sup[which(imcs_sup == imc_sup)], 
                  loc_inf[which(imcs_inf == imc_inf)])
        newcut <- newcut[-setdiff(loc_imcs, keep),]
      }
      if ("root" %in% newcut$var2 && length(newcut$var2) > 1) {
        newcut <- newcut[-1, ]
      }
    }
    if (type_var[var == v] == "categorical") {
      index <- grep(v, newcut$var2, fixed = TRUE)
      l <- index[-length(index)]
      if (length(l) > 0) {
        newcut <- newcut[-l, ]
      }
      if ("root" %in% newcut$var2) {
        newcut <- newcut[-1, ]
      }
    }
  }
  
  if(mediation){
    tab <- data.frame(subgroup=paste(unique(newcut$var2), collapse=" & ") |> rep(length(treat)),
                      proba.mediator=unlist(proba),
                      mediator=treat,
                      subgroup.size=n |> rep(length(treat)),
                      subgroup.rel.size=pourcent |> rep(length(treat)),
                      row.names = NULL)
  }else{
    tab <- data.frame(subgroup=paste(unique(newcut$var2), collapse=" & ") |> rep(length(treat)),
                      proba.exposure=unlist(proba),
                      exposure=treat,
                      subgroup.size=n  |> rep(length(treat)),
                      subgroup.rel.size=pourcent  |> rep(length(treat)),
                      row.names = NULL)
  }
  
  
  return(list(data = newcut, table=tab))
}



#' Update label of an rpart object
#'
#' @param object rpart object
#' @param digits 
#' @param minlength 
#' @param pretty 
#' @param collapse 
#' @param ... 
#'
#' @return return the rpart object with the cutoffs (< or >) included
#'
#' @examples
labels.rpart <- function(object, digits = 4, minlength = 1L, 
                         pretty, collapse = TRUE, ...) {
  if (missing(minlength) && !missing(pretty)) {
    minlength <- if (is.null(pretty)) 
      1L
    else if (is.logical(pretty)) {
      if (pretty) 
        4L
      else 0L
    }
    else 0L
  }
  ff <- object$frame
  n <- nrow(ff)
  if (n == 1L) 
    return("root")
  is.leaf <- (ff$var == "<leaf>")
  whichrow <- !is.leaf
  vnames <- ff$var[whichrow]
  index <- cumsum(c(1, ff$ncompete + ff$nsurrogate + !is.leaf))
  irow <- index[c(whichrow, FALSE)]
  ncat <- object$splits[irow, 2L]
  lsplit <- rsplit <- character(length(irow))
  if (any(ncat < 2L)) {
    jrow <- irow[ncat < 2L]
    formatg <- function(x, digits = getOption("digits"), 
                        format = paste0("%.", digits, "g")) {
      if (!is.numeric(x)) 
        stop("'x' must be a numeric vector")
      temp <- sprintf(format, x)
      if (is.matrix(x)) 
        matrix(temp, nrow = nrow(x))
      else temp
    }
    cutpoint <- formatg(object$splits[jrow, 4L], digits)
    temp1 <- (ifelse(ncat < 0, "< ", ">="))[ncat < 2L]
    temp2 <- (ifelse(ncat < 0, ">=", "< "))[ncat < 2L]
    lsplit[ncat < 2L] <- paste0(temp1, cutpoint)
    rsplit[ncat < 2L] <- paste0(temp2, cutpoint)
  }
  if (any(ncat > 1L)) {
    xlevels <- attr(object, "xlevels")
    jrow <- seq_along(ncat)[ncat > 1L]
    crow <- object$splits[irow[ncat > 1L], 4L]
    cindex <- (match(vnames, names(xlevels)))[ncat > 
                                                1L]
    if (minlength == 1L) {
      if (any(ncat > 52L)) 
        warning("more than 52 levels in a predicting factor, truncated for printout", 
                domain = NA)
    }
    else if (minlength > 1L) 
      xlevels <- lapply(xlevels, abbreviate, minlength, 
                        ...)
    for (i in seq_along(jrow)) {
      j <- jrow[i]
      splits <- object$csplit[crow[i], ]
      cl <- if (minlength == 1L) 
        ""
      else ","
      lsplit[j] <- paste((xlevels[[cindex[i]]])[splits == 
                                                  1L], collapse = ",")
      rsplit[j] <- paste((xlevels[[cindex[i]]])[splits == 
                                                  3L], collapse = ",")
    }
  }
  if (!collapse) {
    ltemp <- rtemp <- rep("<leaf>", n)
    ltemp[whichrow] <- lsplit
    rtemp[whichrow] <- rsplit
    return(cbind(ltemp, rtemp))
  }
  lsplit <- paste0(ifelse(ncat < 2L, "", "="), lsplit)
  rsplit <- paste0(ifelse(ncat < 2L, "", "="), rsplit)
  varname <- (as.character(vnames))
  node <- as.numeric(row.names(ff))
  parent <- match(node%/%2L, node[whichrow])
  odd <- (as.logical(node%%2L))
  labels <- character(n)
  labels[odd] <- paste0(varname[parent[odd]], rsplit[parent[odd]])
  labels[!odd] <- paste0(varname[parent[!odd]], lsplit[parent[!odd]])
  labels[1L] <- "root"
  labels
}

#' Found parent node
#'
#' @param x Frame in a rpart object
#'
#' @return return the number of the parent node
#'
#' @examples
parent <- function(x) {
  if (x[1] != 1) 
    c(Recall(if (x%%2 == 0L) x/2 else (x - 1)/2), 
      x)
  else x
}



#' Positivity Regression trees
#'
#' Check the positivity assumption and identify problematic subgroups/covariables.
#'
#' @param group Label of the column related to the exposure
#' @param type_expo Type of the exposure ('b' for binary, 'c' for continuous, or 'n' for nominal)
#' @param cov.quanti Columns' labels of the quantitative variables in the adjustment set
#' @param cov.quali Columns' labels of the qualitative variables in the adjustment set
#' @param data Dataset, must be a data.frame object
#' @param alpha Subgroup minimal size (as a proportion of the whole sample)
#' @param beta Threshold for non-positivity (i.e., extreme exposure's probability). 
#' @param gamma Maximal number of variables to define a subgroup
#' @param mediation Boolean, is the exposure a mediator?
#' @param graph Provide the trees as additional output?
#' @param pruning Boolean, should we keep the 'internal' violation (e.g., >30 & <40)
#' @param minbucket Rpart hyperparameter, minimum number of individual in the leaves
#' @param minsplit Rpart hyperparameter, minimum number of individual in a node to be split
#' @param maxdepth Rpart hyperparameter, maximum number of successive nodes
#' @param tweak Text size for the graphs
#'
#' @return Data.frame with all poisity violations (subgroup name | exposure probability | exposure level | subgroup size (N) | subgroup relative size (%))
#' @export
#'
#' @examples
port <- function (group, type_expo="b", cov.quanti, cov.quali, data, alpha = 0.05, beta = 'gruber', gamma = 2, mediation=FALSE, graph="none", pruning = FALSE, minbucket = 6, minsplit = 20, maxdepth = 30, tweak=1){
  if (!(is.data.frame(data) | is.matrix(data))){
    stop("The argument \'data\' need to be a data.frame or a matrix")
  }
  if (alpha > 0.5 | alpha < 0) 
    stop("The argument \'alpha\' must be a proportion (e.g., 0.05 for 5%).")
  if(beta=='gruber') beta <- 5/(sqrt(nrow(data))*log(nrow(data)))
  if (beta > 1 | beta <= 0) 
    stop("The argument \'beta\' must be a non-null proportion (e.g., 0.05 for 5%).")
  if(type_expo=="b"){
    if (!all(names(table(data[, group])) == c("0","1"))) {
      stop("Two modalities encoded 0 (for non-treated/non-exposed patients) and 1 (for treated/exposed patients) are required in the argument \'group\' when the argument \'type_expo\' is \'b\' (i.e., binary).")
    }
  }
  if (type_expo=="c") { # categorisation according to the quartiles
    data[, group] <- as.factor(cut(data[, group], breaks = quantile(data[, group], seq(0, 1, by = 0.25), na.rm = FALSE)))
  }
  if(type_expo=="n"){ # nominal
    data[, group] <- as.factor(data[,group])
    if(length(levels(data[,group])) < 3){
      stop("At least three modalities are required in the argument \'group\' when the argument \'type_expo\' is \'n\' (i.e., nominal).")
    }
  }
  
  if(length(cov.quali)>1){
    data[, cov.quali] <- apply(data[, cov.quali], 2, as.factor)
  }else{
    if(length(cov.quali)==1) data[, cov.quali] <- as.factor(data[, cov.quali])
  }
  
  covariates <- c(cov.quanti, cov.quali)
  m <- length(covariates)
  up <- sapply(1:gamma, function(x) ncol(combn(m,x)))
  savegraph <- problem_covariates <- problem_cutoffs <- list()
  
  combi <- sapply(1:gamma, function(x) combn(m, x) |> split(f=col(combn(m, x))) |> unname() ) |> unlist(recursive = FALSE)
  
  for (q in 1:length(combi)) { 
    if (q %in% (up+1)) { # remove problematic covariates already identified when gamma is updated
      if (length(problem_cutoffs) > 0) {
        var_prob <- problem_covariates |> unlist() |> unique()
        bad_cov <- which(covariates %in% var_prob)
      }
    }
    if (exists("bad_cov") && any(bad_cov %in% combi[[q]])) { #pass combination if violation found in a predictor involved inside 
      next
    }
    covariables <- covariates[combi[[q]]]
    cart_max <- rpart::rpart(reformulate(covariables, group), data = data, cp = 0, minbucket = minbucket, method = ifelse(type_expo=="b", "anova", "class"), minsplit = minsplit, maxdepth = maxdepth)
    frame <- cart_max$frame
    frame$var2 <- labels.rpart(cart_max)
    if (nrow(frame) > 1) {
      for (j in 2:nrow(frame)) {
        for (cov in covariables) {
          if (grepl(cov, frame$var2[j])) {
            frame$var[j] <- cov
          }
        }
      }
    }
    problematic_nodes <- numeric(0)
    if(type_expo=="b"){
      for (i in 1:nrow(frame)) { #read tree with alpha & beta -> save problematic nodes
        if ((frame$yval[i] >= 1 - beta || frame$yval[i] <= 
             beta) && frame$n[i] >= nrow(data) * alpha) {
          problematic_nodes <- c(problematic_nodes, as.numeric(rownames(frame)[i]))
        }
      }
    }else{
      p_a <- data.frame(matrix(frame$yval2[,(length(table(data[,group]))+2):(dim(frame$yval2)[2]-1)], ncol = length(levels(data[,group])))) |> setNames(nm = levels(data[,group])) #keep proba of each exposure modality
      for (i in 1:nrow(frame)) { #read tree with alpha & beta -> save problematic nodes
        if (any( (p_a[i,] >= 1 - beta | p_a[i,] <= 
                  beta) & frame$n[i] >= nrow(data) * alpha )) {
          problematic_nodes <- c(problematic_nodes, as.numeric(rownames(frame)[i]))
        }
      }
    }
    for (n in problematic_nodes) { #check if a node is an ancestor of another, if yes keep the ancestor. 
      for (p in parent(n)[-length(parent(n))]) {
        if (p %in% problematic_nodes) {
          problematic_nodes <- problematic_nodes[!problematic_nodes == n]
        }
      }
    }
    
    problematic_path <- list()
    for (i in problematic_nodes) { # save the path from root to the pb node
      problematic_path[[as.character(i)]] <- frame[which(rownames(frame) %in% parent(i)), c("var", "var2", "n")]
      if(type_expo=="b"){
        problematic_path[[as.character(i)]]$proba <- frame$yval[which(rownames(frame) %in%  parent(i))]
      }else{
        problematic_path[[as.character(i)]]$proba <- p_a[which(rownames(frame) %in%  parent(i)),]
      }
      
    }
    problem_names <- 1
    for (i in names(problematic_path)) {
      problem_names <- c(rownames(problematic_path[[i]]), problem_names)
    }
    problem_names <- unique(problem_names)
    
    ####
    if(graph!="none"){
      cols<-ifelse(as.numeric(row.names(cart_max$frame)) %in% problem_names,"red","blue")
      rpart.plot::rpart.plot(cart_max, branch.col=cols, tweak=tweak) |> suppressWarnings() 
      savegraph[[q]] <- list(tree=recordPlot(load=c("rpart", "rpart.plot")), problem=ifelse(length(problematic_path) != 0, TRUE, FALSE))
    }
    ###
    
    if (length(problematic_path) > 0) { # save all new prb path in problem_cutoff (can thereby reuse problematic_path for the next iteration) 
      for (k in 1:length(problematic_path)){
        if (length(problem_cutoffs) == 0 || !any(sapply(problem_cutoffs, problematic_path[k][[names(problematic_path[k])]], FUN = identical)) ) {
          problem_cutoffs[[as.character(length(problem_cutoffs) + 1)]] <- problematic_path[k][[names(problematic_path[k])]]
          problem_covariates[[as.character(length(problem_covariates) + 1)]] <- covariables
        }
      }
    }  
  } # end of the "q" for-loop
  
  res <- data.frame()
  if (length(problem_cutoffs) > 0) {
    for (i in 1:length(problem_cutoffs)) {
      vars <- unique(problem_cutoffs[[i]]$var)
      type <- character(length(vars))
      for (k in 1:length(vars)) {
        type[k] <- ifelse(vars[k] %in% cov.quanti, "continuous", "categorical")
      }
      problem_covariates[[i]] <- paste(problem_covariates[[i]],  collapse = ";")
      cut <- define_cutoff(problem_cutoffs[[i]], vars, type_var=type, data, pruning = pruning, type_expo, mediation, beta, group)
      
      if (is.null(cut$data)) {
        problem_cutoffs[[i]] <- NULL
        problem_covariates[[i]] <- NULL
      }else {
        problem_cutoffs[[i]] <- cut$data
        if(cut$table$subgroup=='root') return("The whole sample presents an exposure prevalence higher than \'beta\'.")
      }
      
      
      res <- rbind(res, cut$table)
      
    }
    
    if(graph!="none") savegraph <- savegraph[which(sapply(lapply(savegraph, '[[', 'problem'), function(x) !is.null(x)))] #cut null result from tree not built because an one-variable violation was found
    
    output <- switch(graph,
                     all=list(
                       table = res, 
                       problematic.graphs = lapply(savegraph[sapply(savegraph, '[[', 'problem')], '[[', 'tree'), 
                       correct.graphs = lapply(savegraph[!sapply(savegraph, '[[', 'problem')], '[[', 'tree')
                     ),
                     none=res,
                     prob=list(
                       table = res, 
                       problematic.graphs = lapply(savegraph[sapply(savegraph, '[[', 'problem')], '[[', 'tree')
                     ),
                     correct=list(
                       table = res, 
                       correct.graphs = lapply(savegraph[!sapply(savegraph, '[[', 'problem')], '[[', 'tree')
                     )
    )
    
  }else{
    
    output <- "No problematic subgroup was identified."  
    
  }
  
  return(output)
}

