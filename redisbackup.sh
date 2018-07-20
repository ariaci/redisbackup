#!/bin/bash

# redisbackup v1.0
#
# Copyright 2017 Patrick Morgenstern (ariaci)
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#
# Script to make automatic backups of all your Redis databases
# on QNAP devices based on mysqlbackup of Kenneth Friebert
#
# Thanks to Kenneth Fribert for mysqlbackup (https://forum.qnap.com/viewtopic.php?t=15628)
#

# Standard commands used in this script
rm_c="/bin/rm"
tar_c="/bin/tar"
get_c="/sbin/getcfg"
ec_c="/bin/echo"
log_c="/sbin/write_log"
md_c="/bin/mkdir"
ls_c="/bin/ls"
date_c="/bin/date"

if [ ! -e "$get_c" ] ; then get_c="$(dirname "$0")/redisbackup_getcfg.sh" ; fi

# Check config file to use
if [[ -z "$1" ]] ; then config="/etc/config/redisbackup.conf" ; else config=$1 ; fi
if [ ! -e "$config" ] ; then
   $ec_c -e "Redis Backup: ERROR: configuration file not found"
   if [ -e "$log_c" ] ; then $log_c "Redis Backup: ERROR configuration file not found" 1 ; fi
   exit 1
fi

# Read config file
day_ret=$($get_c redisbackup day_retention -f "$config")
week_ret=$($get_c redisbackup week_retention -f "$config")
month_ret=$($get_c redisbackup month_retention -f "$config")
weekday_rot=$($get_c redisbackup day_rotate -f "$config")
share=$($get_c redisbackup share -f "$config")
sharetype=$($get_c redisbackup sharetype -f "$config")
folder=$($get_c redisbackup folder -f "$config")
pw=$($get_c redisbackup pw -f "$config")
level=$($get_c redisbackup errorlvl -f "$config")
searchfolders=$($get_c redisbackup searchfolders -f "$config")
server=$($get_c redisbackup server -f "$config")
port=$($get_c redisbackup port -f "$config")

# If logger command isn't available set loglevel=0 to supress logging
if [ ! -e "$log_c" ] ; then level=0 ; fi

# Internal variable setup
arc=$($date_c +%y%m%d).tar.gz
dest=
cur_month_day=$($date_c +"%d")
cur_week_day=$($date_c +"%u")
rediscli_p=
rediscli_c=
error=
databases=
bkup_p=

# Error and logging functions

function error () {
   $ec_c -e "Redis Backup: ERROR: $1"
   if test "$level" -gt 0 ; then
      $log_c "Redis Backup: ERROR $1" 1
   fi
   exit 1
}

function warn () {
   $ec_c -e "Redis Backup: WARNING: $1"
   if test "$level" -gt 1 ; then
      $log_c "Redis Backup: WARNING $1" 2
   fi
}

function info () {
   $ec_c -e "Redis Backup: INFO: $1"
   if test "$level" -gt 2 ; then
      $log_c "Redis Backup: INFO $1" 4
   fi
}

# Functions for handling PID file

function pidfilename() {
  myfile=$(basename "$0" .sh)
  whoiam=$(whoami)
  mypidfile=/tmp/$myfile.pid
  [[ "$whoiam" == 'root' ]] && mypidfile=/var/run/$myfile.pid
  echo $mypidfile
}

function cleanup () {
  trap - INT TERM EXIT
  [[ -f "$mypidfile" ]] && rm "$mypidfile"
  exit
}

function isrunning() {
  pidfile="$1"
  [[ ! -f "$pidfile" ]] && return 1
  procpid=$(<"$pidfile")
  [[ -z "$procpid" ]] && return 1
  [[ ! $(ps -p $procpid | grep $(basename $0)) == "" ]] && value=0 || value=1
  return $value
}

function createpidfile() {
  mypid=$1
  pidfile=$2
  $(exec 2>&-; set -o noclobber; echo "$mypid" > "$pidfile") 
  [[ ! -f "$pidfile" ]] && exit #Lock file creation failed
  procpid=$(<"$pidfile")
  [[ $mypid -ne $procpid ]] && {
    isrunning "$pidfile" || {
      rm "$pidfile"
      $0 $@ &
    }
    {
    echo "redisbackup is already running, exiting"
    exit
    }
  }
}

# Start script
mypidfile=$(pidfilename)
createpidfile $$ "$mypidfile"
trap 'cleanup' INT TERM EXIT

# Checking if prerequisites are met
if [[ -z "$level" ]] ; then level="0" ; warnlater="Errorlevel not set in config, setting to 0 (nothing)" ; fi
$ec_c -e "\n"
info "Redis Backup STARTED"

# Checking variables from config file
if [[ -n "$warnlater" ]] ; then warn "$warnlater" ; fi 
if [[ -z "$day_ret" ]] ; then day_ret="6" ; warn "days to keep backup not set in config, setting to 6" ; fi
if [[ -z "$week_ret" ]] ; then week_ret="5" ; warn "weeks to keep backup not set in config, setting to 5" ; fi
if [[ -z "$month_ret" ]] ; then month_ret="3" ; warn "months to keep backup not set in config, setting to 3" ; fi
if [[ -z "$weekday_rot" ]] ; then weekday_rot="0" ; warn "weekly rotate day not set in config, setting to sunday" ; fi
if [[ -z "$share" ]] ; then share="Backup" ; warn "share for storing backup not set in config, setting to Backup" ; fi
if [[ -z "$sharetype" ]] ; then sharetype="smb:qnap" ; info "sharetype for storing backup not set in config, setting to smb:qnap" ; fi
if [[ -z "$searchfolders" ]] ; then searchfolders="/usr/local" ; info "Redis searchfolders for backup not set in config, setting 
to default for library/redis:latest-docker-image" ; fi
if [[ -z "$server" ]] ; then server="127.0.0.1" ; info "Redis server for backup not set in config, setting to 127.0.0.1" ; fi
if [[ -z "$port" ]] ; then port="6379" ; info "Redis server port for backup not set in config, setting to 6379" ; fi

# Check for backup share using sharetype
case $(tr '[:upper:]' '[:lower:]' <<<"$sharetype") in
   "smb:qnap")
      bkup_p=$($get_c "$share" path -f /etc/config/smb.conf)
      if [ $? != 0 ] ; then error "the share $share is not found, remember that the destination has to be a share" ; else info "Backup smb share found" ; fi
      ;;
   "filesystem")
      bkup_p=$share
      if [ ! -d "$bkup_p" ] ; then error "the share $share is not found in filesystem" ; else info "Backup filesystem share found" ; fi
      ;;
   *)
      error "the sharetype $sharetype is unknown, supported types are smb:qnap or filesystem"
      ;;
esac

# Add subfolder to backup share
if [[ -z "$folder" ]] ; then
   info "No subfolder given";
   else
   {
   info "subfolder given in config";
   bkup_p="$bkup_p"/"$folder";
   # Check for subfolder under share
   $md_c -p "$bkup_p" ; if [ $? != 0 ] ; then error "the backup folder ($folder) under the share could not be created on the share $share" ; fi
   }
fi

# Check for backup folder on backup share
if ! [ -d "$bkup_p/redis" ] ; then info "redis folder missing under $bkup_p, it has been created" ; $md_c "$bkup_p/redis" ; if [ $? != 0 ] ; then error "the folder redis could not be created on the share $share" ; fi ; fi

# Check for day retention folder on backup share
if ! [ -d "$bkup_p/redis.daily" ] ; then info "redis.daily folder missing under the share $bkup_p, it has been created" ; $md_c "$bkup_p/redis.daily" ; if [ $? != 0 ] ; then error "the folder redis.daily could not be created on the share $share" ; fi ; fi

# Check for week retention folder on backup share
if ! [ -d "$bkup_p/redis.weekly" ] ; then info "redis.weekly folder missing under the share $bkup_p, it has been created" ; $md_c "$bkup_p/redis.weekly" ; if [ $? != 0 ] ; then error "the folder redis.weekly could not be created on the share $share" ; fi ; fi

# Check for month retention folder on backup share
if ! [ -d "$bkup_p/redis.monthly" ] ; then info "redis.monthly folder missing under the share $bkup_p, it has been created" ; $md_c "$bkup_p/redis.monthly" ; if [ $? != 0 ] ; then error "the folder redis.monthly could not be created on the share $share" ; fi ; fi

# Check for redis-cli command
for rediscli_p in $searchfolders; do
  [ -f $rediscli_p/bin/redis-cli ] && rediscli_c="$rediscli_p/bin/redis-cli"
done
if [ -z $rediscli_c ] ; then error "redis-cli command not found."; else info "redis-cli command found" ; fi

# Listing all the databases individually, and dumping them
databases=$(ls $($rediscli_c -u redis://$pw@$server:$port CONFIG GET DIR|tail -1)/*.rdb)
if [ $? != 0 ] ; then error "cannot list databases, is server, port and password correct?" ; fi

# Delete old daily backups
info "Cleaning out old backups. Keeping the last $day_ret daily backups"
full="$bkup_p/redis.daily"
for target in $(ls -t "$full" | tail -n +$(($day_ret + 1 ))) ; do rm -f "$full/$target"; done
if [ $? != 0 ] ; then error "erasing old daily backups" ; fi

# Delete old weekly backups
info "Cleaning out old backups. Keeping the last $week_ret week backups"
full="$bkup_p/redis.weekly"
for target in $(ls -t "$full" | tail -n +$(($week_ret + 1 ))) ; do rm -f "$full/$target"; done
if [ $? != 0 ] ; then error "erasing old weekly backups" ; fi

# Delete old monthly backups
info "Cleaning out old backups. Keeping the last $month_ret montly backups"
full="$bkup_p/redis.monthly"
for target in $(ls -t "$full" | tail -n +$(($month_ret + 1 ))) ; do rm -f "$full/$target"; done
if [ $? != 0 ] ; then error "erasing old monthly backups" ; fi

# Save current state and all pending changes of all databases
info "Syncing current state and all pending changes of all Redis databases to disk"
$rediscli_c -u redis://$pw@$server:$port SAVE
if [ $? != 0 ] ; then error "cannot sync state and databases to disk, is server, port and password correct?" ; fi

info "Backing up current databases to $bkup_p/redis"
while read line
do
  set $line
  $ec_c -e "Backing up database $line"
  cp "$line" "$bkup_p/redis/"
  if [ $? != 0 ]; then error "creating new backup when trying to access the database $line" ; error=error ; fi
done<<<"$databases"

if [[ -z $error ]] ; then info "Backup Successfull" ; else error "Backup encountered errors, please investigate" ; fi

# Compress backup to an seleced archive

# On first month day do
if [ $cur_month_day == 01 ] ; then
  {
  dest=redis.monthly;
  info "Creating a monthly archive";
  }
else
  # On selected weekday do
  if [ $cur_week_day == $weekday_rot ] ; then
    {
    dest=redis.weekly;
    info "Creating a weekly archive";
    }
  else
    # On any regular day do
    {
    dest=redis.daily;
    info "Creating a daily archive";
    }
  fi
fi

info "Compressing backup to $bkup_p/$dest/$arc"
cd "$bkup_p/redis/"
$tar_c 2> /dev/null -czvf "$bkup_p/$dest/$arc" * --remove-files &>/dev/null
if [ $? != 0 ] ; then error "compressing backup" ; else info "Done compressing backup" ; fi

info "Cleaning up after archiving"
$rm_c -f "$bkup_p/redis/*"

info "Redis Backup COMPLETED"
