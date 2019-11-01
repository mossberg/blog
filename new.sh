#!/bin/bash

title=$1
date=`date '+%Y-%m-%d'`
fname=$date-$title.md
hugo new "posts/$fname"
