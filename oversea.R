
############################
# Module
############################

rm(list=ls())
library(MASS)
library(plyr)
library(openxlsx)
library(data.table)
library(dplyr)
library(keras)
library(ggplot2)

#Get Model File
rmna <- function(x){ifelse(is.na(x),0,x)}
get_model_file <- function(x,i,p,gety=TRUE){
  if(gety){y <- t(x[p+i,,drop=F])}
  x <- t(x[1:p+i-1,,drop=F])
  if(gety){y[y<0] <- 0}
  x[x<0] <- 0
  f <- rowMeans(x)
  if(gety){y <- y/f; y[is.na(y)] <- 0; y[y==Inf] <- 0}
  x <- x/f; x[is.na(x)] <- 0
  if(!gety){y <- NULL}
  list(x=x,y=y,f=f,i=i)
}
get_model_xy <- function(x,p,gety,w,sel){
  out <- lapply(1:(nrow(x)-p-gety-sel),get_model_file,x=x,p=p,gety=gety)
  out <- rep(out,ceiling(sapply(out,function(x){x$i})/w))
  X <- do.call(rbind,lapply(out,function(x){x$x}))
  Y <- do.call(rbind,lapply(out,function(x){x$y}))
  list(Y=Y,X=X)
}

#MSAE
MSAE <- function(X,Y,dims,activations,batch,epochs,verbose){
  e.input <- layer_input(shape=ncol(X))
  e.layer <- layer_dense(e.input,dims[1],activation=activations[1])
  l.layer <- layer_dense(e.layer,dims[2],activation=activations[2])
  d.output <- layer_dense(units=ncol(Y),activation=NULL)
  model <- keras_model(e.input,d.output(l.layer))
  encoder <- keras_model(e.input,l.layer)
  d.input <- layer_input(shape=dims[2])
  decoder <- keras_model(d.input,d.output(d.input))
  model %>% compile(
    loss = "mean_squared_error", 
    optimizer = "adam",
    metrics = c('mae')
  )
  system.time(history <- model %>% fit(
    x = X, 
    y = Y,
    batch = batch,
    epochs = epochs,
    verbose = verbose
  ))
  list(model=model,encoder=encoder,decoder=decoder,history=history)
}

#plot
ggstack <- function(temp){
  temp <- data.table(date=as.POSIXct( "2020-01-20") + 3600*24*1:nrow(temp),temp) %>% as.data.frame
  temp <- melt(temp,id='date'); colnames(temp) <- c('Date','Country','Cases')
  temp <- mutate(temp,Country=ifelse(Country%in%c('china','iran','korea','italy','usa'),toupper(Country),'OTHERS'))
  temp <- temp %>% group_by(Date,Country) %>% summarise(Cases=sum(Cases))
  temp <- merge(temp,(temp %>% group_by(Country) %>% summarise(ttl=sum(Cases)) %>% arrange(ttl)),by='Country') %>% arrange(ttl)
  temp$Country <- factor(temp$Country,c('OTHERS',"USA",'ITALY','KOREA','IRAN','CHINA'))
  ggplot(temp,aes(fill=Country,y=Cases,x=Date)) + geom_bar(position="stack", stat="identity")
}

ggline <- function(temp){
  temp <- data.table(date=as.POSIXct( "2020-01-20") + 3600*24*1:nrow(temp),temp) %>% as.data.frame
  temp <- melt(temp,id='date'); colnames(temp) <- c('Date','Country','Cases')
  temp <- mutate(temp,Country=ifelse(Country%in%c('china','iran','korea','italy','usa'),toupper(Country),'OTHERS'))
  temp <- temp %>% group_by(Date,Country) %>% summarise(Cases=sum(Cases))
  temp <- merge(temp,(temp %>% group_by(Country) %>% summarise(ttl=sum(Cases)) %>% arrange(ttl)),by='Country') %>% arrange(ttl)
  temp$Country <- factor(temp$Country,c('OTHERS',"USA",'ITALY','KOREA','IRAN','CHINA'))
  ggplot(temp,aes(colour=Country,y=Cases,x=Date)) + geom_line(size=1)
}

#todate
todate <- function(x){
  x <- as.POSIXct( "2020-01-20") + 3600*24*x
  paste(x)
}

############################
# Data Processing
############################

setwd('/Users/wenrurumon/Documents/posdoc/wuhan')
raw1 <- read.csv("china_confirmed.csv")[,-1]
raw2 <- read.csv("global_confirmed.csv")[,-1:-2]
raw3 <- read.csv("data0305.csv") %>% 
  mutate(state=tolower(state),dead=rmna(death),confirmed=rmna(confirmed)) %>% 
  select(date,state,dead,confirmed)
raw3[raw3$state=='china'&raw3$date<=213,]$confirmed <- rowSums(raw1[11:34,-1])
raw <- raw3; rm(raw1,raw2,raw3)
raw.date <- as.POSIXct( "2020-01-20") + 3600*24*1:length(unique(raw$date))
raw <- lapply(unique(raw$state),function(s){
  x <- filter(raw,state==s)
  list(state = s,
       confirmed = rmna(x$confirmed[match(unique(raw$date),x$date)]),
       dead = rmna(x$dead[match(unique(raw$date),x$date)]))
})
names(raw) <- sapply(raw,function(x){x$state})
raw.c <- sapply(raw,function(x){x$confirmed})
raw.d <- sapply(raw,function(x){x$dead})

rate.d <- raw.d/raw.c
rate.d <- rbind(rate.d[,which(colSums(raw.d)>0)],
                ttl=apply(raw.d,2,max)[which(colSums(raw.d)>0)])
rate.d <- cbind(total=c(rowSums(raw.d)/rowSums(raw.c),ttl=max(rowSums(raw.d))),rate.d)
rwrite.csv(rate.d,'temp.csv')


############################
# Validation
############################

# Y.raw <- rbind(0,raw.c)
# Y.model <- apply(Y.raw,2,diff)
# model.vali <- lapply(1:5,function(sel){
#   w <- 14
#   chinaw <- 10
#   mfile <- get_model_xy(Y.model,p=8,gety=T,w=w,sel=sel)
#   mfile$Y <- mfile$Y[c(1:nrow(mfile$X),rep(which(rownames(mfile$X)=='china'),chinaw)),,drop=F]
#   mfile$X <- mfile$X[c(1:nrow(mfile$X),rep(which(rownames(mfile$X)=='china'),chinaw)),,drop=F]
#   mfile$X <- cbind(mfile$X,state=as.numeric(rownames(mfile$X)=='china'))
#   set.seed(4)
#   models.vali <- lapply(1:5,function(i){
#     print(paste(i,Sys.time()))
#     MSAE(X=mfile$X,Y=mfile$Y,
#          dims=c(32,4),activations=c('relu','relu'),
#          batch=128,epochs=1000,verbose=0)
#   })
#   mfile.vali <- lapply((nrow(Y.model)-9):0,function(i){
#     temp <- get_model_file(x=Y.model,i=nrow(Y.model)-8-i,p=8,gety=FALSE)
#     temp$x <- cbind(temp$x,as.numeric(rownames(temp$x)=='china'))
#     return(temp)
#   })
#   mfile.vali <- rbind(NA,NA,NA,NA,NA,NA,NA,NA,
#                       sapply(mfile.vali,function(x){
#                         x <- sapply(models.vali,function(m){
#                           ((m$model %>% predict(x$x)) * x$f)
#                         }) %>% rowMeans
#                         ifelse(x<0,0,x)
#                       }) %>% t
#   )
#   mfile.vali
# })
# model.vali <- lapply(1:length(model.vali),function(i){
#   x <- model.vali[[i]]
#   for(j in 1:(nrow(x)-i)){x[j,] <- x[j,]+Y.raw[j,]}
#   for(j in (nrow(x)-i+1):nrow(x)){x[j,] <- x[j,]+x[j-1,]}
#   x
# })
# 
# write.csv(cbind(rowSums(Y.raw)[-1],sapply(model.vali,rowSums)
#                 ,rowSums(Y.raw[,-1])[-1],sapply(model.vali,function(x){rowSums(x[,-1])})
#                 ,(Y.raw[,1])[-1],sapply(model.vali,function(x){(x[,1])})),'oversee/model/temp.csv')

############################
# Prediction
############################

#Setup

Y.raw <- rbind(0,raw.c)
Y.model <- apply(Y.raw,2,diff)

#Modeling
# sel <- 0
# w <- 14
# chinaw <- 10
# mfile <- get_model_xy(Y.model,p=8,gety=T,w=w,sel=sel)
# mfile$Y <- mfile$Y[c(1:nrow(mfile$X),rep(which(rownames(mfile$X)=='china'),chinaw)),,drop=F]
# mfile$X <- mfile$X[c(1:nrow(mfile$X),rep(which(rownames(mfile$X)=='china'),chinaw)),,drop=F]
# mfile$X <- cbind(mfile$X,state=as.numeric(rownames(mfile$X)=='china'))
# set.seed(4)
# models.pred <- lapply(1:5,function(i){
#   print(paste(i,Sys.time()))
#   MSAE(X=mfile$X,Y=mfile$Y,
#        dims=c(32,4),activations=c('relu','relu'),
#        batch=128,epochs=1000,verbose=0)
# })

#models.pred
setwd("/Users/wenrurumon/Documents/posdoc/wuhan/oversee/model")
models.pred <- lapply(dir(pattern='.model'),function(x){
  list(model=keras::load_model_hdf5(x))
})

#Prediction
rlts <- list()
mfile.pred <- lapply((nrow(Y.model)-9):0,function(i){
  temp <- get_model_file(x=Y.model,i=nrow(Y.model)-8-i,p=8,gety=FALSE)
  temp$x <- cbind(temp$x,as.numeric(rownames(temp$x)=='china'))
  return(temp)
})
mfile.pred <- rbind(NA,NA,NA,NA,NA,NA,NA,NA,
                    sapply(mfile.pred,function(x){
                      x <- sapply(models.pred,function(m){
                        ((m$model %>% predict(x$x)) * x$f)
                      }) %>% rowMeans
                      ifelse(x<0,0,x)
                    }) %>% t
)
Y.actual <- (Y.model + Y.raw[-nrow(Y.raw),])
Y.fit <- (mfile.pred + Y.raw[-nrow(Y.raw),])
Y.predict <- Y.fit

#Simulation - defense ASAP
temp <- Y.model
for(i in 1:300){
  x1 <- x2 <- x3 <- get_model_file(temp,i=nrow(temp)-7,p=8,gety=F)
  x1$x <- cbind(x1$x,1); x1$x[rownames(x1$x)=='china',9] <- 1
  x2$x <- cbind(x2$x,0.5); x2$x[rownames(x2$x)=='china',9] <- 1
  x3$x <- cbind(x3$x,0); x3$x[rownames(x3$x)=='china',9] <- 1
  x1 <- (sapply(models.pred,function(m){m$model %>% predict(x1$x)}) * x1$f) %>% rowMeans
  x2 <- (sapply(models.pred,function(m){m$model %>% predict(x2$x)}) * x2$f) %>% rowMeans
  x3 <- (sapply(models.pred,function(m){m$model %>% predict(x3$x)}) * x3$f) %>% rowMeans
  x1 <- ifelse(x1<0,0,x1); x2 <- ifelse(x2<x1,x1,x2); x3 <- ifelse(x3<x2,x2,x3)
  if(i %in% 1:7){temp <- rbind(temp,x1)}else{temp <- rbind(temp,x1)}
}
temp[-1:-nrow(Y.actual),apply(Y.model,2,function(x){sum(x>0)<5})] <- 0
rlts[[length(rlts)+1]] <- temp
ggstack(temp[1:150,])
# for(i in 1:5){keras::save_model_hdf5(models.pred[[i]]$model,paste0('osmodel',i,'.model'),overwrite = TRUE,include_optimizer = TRUE)}

# Other Scenarios
#0.5,1
temp <- Y.model
for(i in 1:300){
  x1 <- x2 <- x3 <- get_model_file(temp,i=nrow(temp)-7,p=8,gety=F)
  x1$x <- cbind(x1$x,1); x1$x[rownames(x1$x)=='china',9] <- 1
  x2$x <- cbind(x2$x,0.5); x2$x[rownames(x2$x)=='china',9] <- 1
  x3$x <- cbind(x3$x,0); x3$x[rownames(x3$x)=='china',9] <- 1
  x1 <- (sapply(models.pred,function(m){m$model %>% predict(x1$x)}) * x1$f) %>% rowMeans
  x2 <- (sapply(models.pred,function(m){m$model %>% predict(x2$x)}) * x2$f) %>% rowMeans
  x3 <- (sapply(models.pred,function(m){m$model %>% predict(x3$x)}) * x3$f) %>% rowMeans
  x1 <- ifelse(x1<0,0,x1); x2 <- ifelse(x2<x1,x1,x2); x3 <- ifelse(x3<x2,x2,x3)
  if(i %in% 1:7){temp <- rbind(temp,x2)}else{temp <- rbind(temp,x1)}
}
temp[-1:-nrow(Y.actual),apply(Y.model,2,function(x){sum(x>0)<5})] <- 0
rlts[[length(rlts)+1]] <- temp
ggstack(temp[1:150,])

#0,0.5,1
temp <- Y.model
for(i in 1:300){
  x1 <- x2 <- x3 <- get_model_file(temp,i=nrow(temp)-7,p=8,gety=F)
  x1$x <- cbind(x1$x,1); x1$x[rownames(x1$x)=='china',9] <- 1
  x2$x <- cbind(x2$x,0.5); x2$x[rownames(x2$x)=='china',9] <- 1
  x3$x <- cbind(x3$x,0); x3$x[rownames(x3$x)=='china',9] <- 1
  x1 <- (sapply(models.pred,function(m){m$model %>% predict(x1$x)}) * x1$f) %>% rowMeans
  x2 <- (sapply(models.pred,function(m){m$model %>% predict(x2$x)}) * x2$f) %>% rowMeans
  x3 <- (sapply(models.pred,function(m){m$model %>% predict(x3$x)}) * x3$f) %>% rowMeans
  x1 <- ifelse(x1<0,0,x1); x2 <- ifelse(x2<x1,x1,x2); x3 <- ifelse(x3<x2,x2,x3)
  if(i %in% 1:7){
    temp <- rbind(temp,x3)
  }else if(i%in%8:14){
    temp <- rbind(temp,x2)
  } else {
    temp <- rbind(temp,x1)
  }
}
temp[-1:-nrow(Y.actual),apply(Y.model,2,function(x){sum(x>0)<5})] <- 0
rlts[[length(rlts)+1]] <- temp
ggstack(temp[1:150,])

#0,0.5,0.5,0.5,1
temp <- Y.model
for(i in 1:300){
  x1 <- x2 <- x3 <- get_model_file(temp,i=nrow(temp)-7,p=8,gety=F)
  x1$x <- cbind(x1$x,1); x1$x[rownames(x1$x)=='china',9] <- 1
  x2$x <- cbind(x2$x,0.5); x2$x[rownames(x2$x)=='china',9] <- 1
  x3$x <- cbind(x3$x,0); x3$x[rownames(x3$x)=='china',9] <- 1
  x1 <- (sapply(models.pred,function(m){m$model %>% predict(x1$x)}) * x1$f) %>% rowMeans
  x2 <- (sapply(models.pred,function(m){m$model %>% predict(x2$x)}) * x2$f) %>% rowMeans
  x3 <- (sapply(models.pred,function(m){m$model %>% predict(x3$x)}) * x3$f) %>% rowMeans
  x1 <- ifelse(x1<0,0,x1); x2 <- ifelse(x2<x1,x1,x2); x3 <- ifelse(x3<x2,x2,x3)
  if(i %in% 1:7){
    temp <- rbind(temp,x3)
  }else if(i%in%8:28){
    temp <- rbind(temp,x2)
  } else {
    temp <- rbind(temp,x1)
  }
}
temp[-1:-nrow(Y.actual),apply(Y.model,2,function(x){sum(x>0)<5})] <- 0
rlts[[length(rlts)+1]] <- temp
ggstack(temp[1:150,])

######################
#Summary
######################

#diff2
rlts.diff <- lapply(rlts,function(x){
  x <- apply(x,2,function(x){x/max(x)})
  x <- apply(x,2,diff)
  x
})
for(i in 1:4){
  write.csv(rlts.diff[[i]],
            paste0("/Users/wenrurumon/Documents/posdoc/wuhan/oversee/model/diff2_",i,'.csv')
            )
}

#CSV
rlts.index <- lapply(rlts,function(x){
  x <- round(x)
  x.date_begin <- apply(x,2,function(x){which(x>0)[1]})
  x.date_max <- apply(x,2,function(x){which(x==max(x))[1]})
  x.date_end <- apply(x,2,function(x){max(which(x>0))})
  x.value_max <- sapply(1:length(x.date_max),function(i){apply(x,2,cumsum)[x.date_max[i],i]})
  x.value2_max <- apply(x,2,max)
  x.value_end <- apply(x,2,sum)
  x.value_now <- colSums(x[1:nrow(Y.model),])
  x.duration <- x.date_end-x.date_begin
  # x.date_begin <- todate(x.date_begin)
  # x.date_max<- todate(x.date_max)
  # x.date_end <- todate(x.date_end)
  data.table(state=colnames(Y.raw),
             date_begin=x.date_begin,date_max=x.date_max,date_end=x.date_end,
             duration=x.duration,value_max=x.value_max,value2_max=x.value2_max,
             value_now=x.value_now,value_end=x.value_end)
  })
for(i in 2:4){
  rlts.index[[i]]$value_end <- ifelse(rlts.index[[i]]$value_end>rlts.index[[i-1]]$value_end,rlts.index[[i]]$value_end,rlts.index[[i-1]]$value_end)
  rlts.index[[i]]$date_end <- ifelse(rlts.index[[i]]$date_end>rlts.index[[i-1]]$date_end,rlts.index[[i]]$date_end,rlts.index[[i-1]]$date_end)
}
rlts.index <- lapply(1:4,function(i){
  temp <- c(nrow(Y.raw),nrow(Y.raw)+7,nrow(Y.raw)+14,nrow(Y.raw)+28)
  idxi <- rlts.index[[i]]
  diffi <- rlts.diff[[i]]
  data.table(idxi,sapply(1:nrow(idxi),function(j){
    c(slopeup = mean(diffi[1:(temp[i]-1),j]),
      slopedown = mean(diffi[c(temp[i]:(idxi$date_end[j]-1)),j]))
  }) %>% t) %>% mutate(date_begin=todate(date_begin),
                       date_max=todate(date_max),
                       date_end=todate(date_end))
})
mean(rlts.diff[[1]][1:129,1])
setwd("/Users/wenrurumon/Documents/posdoc/wuhan/oversee/model")
write.csv(do.call(cbind,rlts.index),'temp.csv')

#Risk Calculation
# rlts.index <- do.call(cbind,rlts.index)
# rlt <- data.table(state=rlts.index[,c(1,4,8)],rlts.index[,colnames(rlts.index) %in% c('date_end','value_end')])
# for(i in c(4,6,8,10)){
#   rlt <- cbind(rlt,risk_date=rlt[[i]]-rlt[[2]])
#   rlt <- cbind(rlt,risk_value=rlt[[i+1]]-rlt[[3]])
# }
# colnames(rlt) <- c('state',
#   paste(rep(c('date_end','value_end'),4),rep(c('now','scenario1','scenario2','scenario3','scenario4'),each=2),sep='_'),
#   paste(rep(c('risk_date','risk_end'),4),rep(c('scenario1','scenario2','scenario3','scenario4'),each=2),sep='_'))
# write.csv(rlt,'temp.csv')
