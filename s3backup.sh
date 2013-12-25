#!/bin/bash
# Description: Backup of Mercurial repositories from a Mercurial server to Amazon S3
# Author: Sasa Brkic (sasa.brkic@cs-computing.com)
#

SOURCEDIR="/path/to/repos"
BACKUPDIR="/path/to/backup/directory"
LOGDIR="/path/to/log/directory"
DAYSTOKEEP=14

HTTPSERVER="httpd"

S3DEST="s3://your-bucket-name/"

init()
{
	# Initialize variables.
	TIMESTAMP=$(date "+%F_%H-%M-%S")
	WORKINGDIR=$BACKUPDIR/working
	UPLOADDIR=$BACKUPDIR/upload

	# Create log file and add header.
	if [ -d $LOGDIR ]
	then
		LOGFILE=$LOGDIR/hg-backup_$TIMESTAMP.log
		echo "***** Starting Backup of the Mercurial Environment *****" > $LOGFILE
		echo "" >> $LOGFILE
	else
		mkdir -p $LOGDIR;
		LOGFILE=$LOGDIR/hg-backup_$TIMESTAMP.log
		echo "***** Starting Backup of the Mercurial Environment *****" > $LOGFILE
		echo "" >> $LOGFILE
		log "Log directory missing, creating new."
	fi
	
	# Check backup directories and create if missing.
	if [ ! -d $WORKINGDIR ]
	then
		mkdir -p $WORKINGDIR
		log "Working directory missing, creating new."
	fi

	if [ ! -d $UPLOADDIR ]
	then
		mkdir -p $UPLOADDIR
		log "Upload directory missing, creating new."
	fi

	return 0
}

cleanup()
{
	# Do some housekeeping.
	# Delete expired log files.
	
	log "Checking expired log files."
	file_number=$(find $LOGDIR/hg-backup_*.log -type f -mtime +$DAYSTOKEEP | wc -l)
	if [ $file_number -gt 0 ]
	then
		log "Found $file_number expired log file(s). Deleting."
		find $LOGDIR/hg-backup_*.log -type f -mtime +$DAYSTOKEEP -delete
	else
		log "No expired log files found."
	fi
	
	echo "" >> $LOGFILE
	echo "***** Finished Backup of the Mercurial Environment *****" >> $LOGFILE
	return 0
}

log()
{
	# Application logging.
	log_time=$(date "+%F %R")
	echo "[$log_time] ${1}" >> $LOGFILE
	if [ $verbose -eq 1 ]
	then
		echo "${1}"
	fi
	return 0
}

usage()
{
	echo ""
	echo "This script is used for backing-up Mercurial repositories to Amazon S3."
	echo "Usage: $0 { OPTION }"
	echo "where OPTION:"
	echo "-v | --verbose  Outputs log entries to console."
	echo "-h | --help     This help."
	echo ""
	return 0
}

shutdown_http()
{
	if [ $(ps -ef | grep -v grep | grep $HTTPSERVER | wc -l) -gt 0 ]
	then
		log "Web server is running, stopping it now."
		error_message=$(service $HTTPSERVER stop)
		status=$?
		if [ $status -eq 0 ]
		then
			log "Web server successfully stopped."
			return 0
		else
			log "There was an error stopping the web server:"$'\n'$error_message
			return 1
		fi
	fi
}

copy_files()
{
	log "Copying Mercurial repositories."
	error_message=$(cp -a $SOURCEDIR $WORKINGDIR)
	status=$?
	if [ $status -eq 0 ]
	then
		# Get number of repositories in the source directory.
		# find returns source directory as well, so we need to subtract 1.
		num_dir=$(find $SOURCEDIR -maxdepth 1 -type d | wc -l)	
		num_repo=$(($num_dir - 1))
		repos=$(ls $SOURCEDIR)
		log "Successfully copied "$num_repo" Mercurial repositories:"$'\n'"$repos"
		return 0
	else
		log "There was an error copying Mercurial repositories:"$'\n'$error_message
		return 1
	fi
}

start_http()
{
	if [ $(ps -ef | grep -v grep | grep $HTTPSERVER | wc -l) -eq 0 ]
	then
		log "Web server is not running, starting it now."
		error_message=$(service $HTTPSERVER start)
		status=$?
		if [ $status -eq 0 ]
		then
			log "Web server successfully started."
			return 0
		else
			log "There was an error starting the web server:"$'\n'$error_message
			return 1
		fi
	fi
}

prepare_archive()
{
	ARCHIVE=$UPLOADDIR/mercurial_$TIMESTAMP.tar.gz
	log "Storing Mercurial repositories in archive:"$'\n'$ARCHIVE
	cd $WORKINGDIR
	error_message=$(tar czPpf $ARCHIVE * 2>&1 1>/dev/null)
	status=$?
	if [ $status -eq 0 ]
	then
		log "Repository archive created successfully."
		rm -fr $WORKINGDIR/*
		return 0
	else
		log "There was an error creating repository archive:"$'\n'$error_message
		rm -fr $WORKINGDIR/*
		rm -f $ARCHIVE
		return 1
	fi
}

upload_archive()
{
	log "Uploading archives to S3."
	num_arch=$(find $UPLOADDIR -maxdepth 1 -type f | wc -l)
	if [ $num_arch -gt 1 ]
	then
		log "Archives from previous backup found. They will be uploaded as well."
	fi
	error_message=$(s3cmd put $UPLOADDIR/* $S3DEST 2>&1 1>/dev/null)
	status=$?
	if [ $status -eq 0 ]
	then
		log "Successfully uploaded "$num_arch" repositories to S3".
		rm -fr $UPLOADDIR/*
		return 0
	else
		log "There was an error uploading archives to S3:"$'\n'$error_message
		return 1
	fi
}

# Main Script

run()
{
	init
	shutdown_http
	if [ $? -eq 0 ]
	then
		copy_files
		start_http
		prepare_archive
	else
		log "Web server did not stop successfully. Aborting backup operations."
		start_http
	fi
	upload_archive
	cleanup
}

verbose=0
param1=$1

case $param1 in
	-v | --verbose)
		verbose=1
		run
		exit
	;;
	-h | --help)
		usage
		exit
	;;
	* )
		run
		exit
esac
