#!/bin/bash
#
#
# Copyright (c) 2020 by Illumio. All rights reserved.
#
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Copyright (c) 2020 by Illumio. All rights reserved.
#
# Author  : Edward de los Santos
# Script  : pcebackup.sh
# Comments: Script to backup PCE database
#           Version supported: 19.3.x, 21.x, 22.x
# Version : 2.2
# Rev Date: 02-2024


BASEDIR=$(dirname $0)
PROG=$(basename $0)
DTE=$(date '+%Y%m%d.%H%M%S' | tr -d '\n')
HOSTNAME=$(hostname)
LOGFILE=""
DMPFILE=""
VERSION_BUILD=""
REDIS_IP=""
ILO_RUNTIME_ENV=""
PRODUCT_VERSION=""
HOST_IP=""

log_print() {
   LOG_DTE=$(date '+%Y-%m-%d %H:%M:%S' | tr -d '\n')
   echo "$LOG_DTE $1 $2"
   echo "$LOG_DTE $1 $2" >> $LOGFILE
}

get_version_build() {

   PVFILE="sudo -E -u ilo-pce cat $PRODUCT_VERSION"
   VERSION=$($PVFILE | grep version: | awk '{print $2}')
   BUILD=$($PVFILE | grep build: | awk '{print $2}')
   VERSION_BUILD="$VERSION-$BUILD"
}


# get redis_server status, return 0 if true
is_redis_server() {
   REDIS_IP=$(sudo -E -u ilo-pce illumio-pce-ctl cluster-status | grep agent_traffic_redis_server | awk '{ print $2}')
   [ $(echo $(ifconfig | grep -F $REDIS_IP | wc -l)) -gt 0 ] && return 0 || return 1
}

is_db_master() {
   DBMASTER_TYPE="$1"
   DB_MGMT_PARAM=""
   get_version_build
   BASE_VERSION=$(echo $VERSION | cut -f1 -d\.)

   DB_MGMT_PARAM="is-primary?"

   #REDIS=$(sudo -E -u ilo-pce illumio-pce-ctl cluster-status | grep agent_traffic_redis_server | awk '{ print $2}')
   DBMASTER=$(sudo -E -u ilo-pce illumio-pce-db-management $DBMASTER_TYPE $DB_MGMT_PARAM  | grep -c "^true")

   [ $DBMASTER -gt 0 ] && return 0 || return 1
}


usage() {
   echo
   echo "Usage: $0 -d <directory location> -b [policydb | trafficdb | reportdb | sc_data_dump | all]   [-r retention_period ] [-u remote_user ] [-h remote_host] [-p remote_path ]"
   echo "  -d PCE backup direction location"
   echo "  -r Database backup retention period"
   echo "     Default is 7 days"
   echo "  -m [true|false]"
   echo "     Backup only on master database node"
   echo "  -b [policydb|trafficdb|reportdb|sc_data_dump|all]"
   echo "     where:"
   echo "        policydb => backup policy database"
   echo "        trafficdb => backup traffic database"
   echo "        reportdb => backup reportdb database"
   echo "        sc_data_dump => supercluster data dump"
   echo "        all => backup policy and traffic database"
   echo 
   echo "  Optional: [SCP backup file(s) to remote host]"
   echo "  **** SSH key authentication is required ****"
   echo "  -i SSH key file."
   echo "     Default is ~/.ssh/id_rsa"
   echo "  -u SCP remote user"
   echo "  -h SCP remote host"
   echo "  -p SCP remote destination path"
   echo 
   exit 1
}


pce_dbdump() {
   log_print "INFO" "Dumpfile: $1"  
   BACKUP="$2"
   if [ $BACKUP = "trafficdb"  ]; then
      log_print "INFO" "Backing up the traffic database" 
      log_print "INFO" "sudo -E -u ilo-pce illumio-pce-db-management traffic dump --file $1"
      sudo -E -u ilo-pce illumio-pce-db-management traffic dump --file $1 >> $LOGFILE

      [ $? -gt 0 ] && log_print "ERROR" "Database backup failed!"
   elif [ $BACKUP = "policydb" ]; then
      log_print "INFO" "Backing up the policy database" 
      log_print "INFO" "sudo -E -u ilo-pce illumio-pce-db-management dump --file $1"
      sudo -E -u ilo-pce illumio-pce-db-management dump --file $1 >> $LOGFILE
      [ $? -gt 0 ] && log_print "ERROR" "Database backup failed!"
   elif [ $BACKUP = "reportdb" ]; then
      log_print "INFO" "Backing up the report database" 
      log_print "INFO" "sudo -E -u ilo-pce illumio-pce-db-management report dump --file $1"
      sudo -E -u ilo-pce illumio-pce-db-management report dump --file $1 >> $LOGFILE
      [ $? -gt 0 ] && log_print "ERROR" "Database backup failed!"
   elif [ $BACKUP = "sc_data_dump" ]; then
      log_print "INFO" "Backing up the Supercluster data dump" 
      log_print "INFO" "sudo -E -u ilo-pce illumio-pce-db-management supercluster-data-dump --file $1"
      sudo -E -u ilo-pce illumio-pce-db-management supercluster-data-dump --file $1 >> $LOGFILE
   fi 

   log_print "INFO" "Completed database backup" 
}

scp_remote_host() {
DUMPFILE="$1"
SSHKEY="$2"
RMTUSER="$3"
RMTHOST="$4"
RMTPATH="$5"

   log_print "INFO" "SCPing to remote host $RMTHOST "
   log_print "INFO" "scp -i $SSHKEY "$DUMPFILE" $RMTUSER@$RMTHOST:$RMTPATH/."
   scp -i $SSHKEY "$DUMPFILE" "$RMTUSER@$RMTHOST:$RMTPATH/."
}




# Main Program

for i in $*
do
   case $1 in
      -d) DUMPDIR="$2"; shift 2;;
      -b) BACKUP_TYPE="$2"; shift 2;;
      -r) RETENTION="$2"; shift 2;;
      -i) SSHKEY="$2"; shift 2;;
      -u) RMTUSER="$2"; shift 2;;
      -h) RMTHOST="$2"; shift 2;;
      -p) RMTPATH="$2"; shift 2;;
      -m) DBMASTER_FLAG="$2"; shift 2;;
      -*) usage; exit 1;;
   esac
done

if [ -z $DUMPDIR ]; then
   usage
   exit 1
fi

LOGFILE="$DUMPDIR/$PROG.$BACKUP_TYPE.$DTE"
DMP_PREFIX=""

ILLUMIO_RUNTIME_ENV=$(env | grep ILLUMIO_RUNTIME_ENV | cut -f2 -d=)

# check for illumio runtime env 
if [ -z $ILLUMIO_RUNTIME_ENV ]; then 
   ILO_RUNTIME_ENV="/etc/illumio-pce/runtime_env.yml"
else
   ILO_RUNTIME_ENV=$ILLUMIO_RUNTIME_ENV
   if [ ! -r $ILO_RUNTIME_ENV ]; then
      echo 
      echo "ERROR: Can't read $ILO_RUNTIME_ENV file!"
      echo
      exit 1
   fi
fi

ILLUMIO_RUNTIME_ENV=$ILO_RUNTIME_ENV; export ILLUMIO_RUNTIME_ENV
INSTALL_ROOT=$(grep install_root $ILLUMIO_RUNTIME_ENV | awk '{print $2}' | sed 's/\"//g')
PRODUCT_VERSION="$INSTALL_ROOT/illumio/product_version.yml"

get_version_build
[ $VERSION_BUILD = "" ] && DMP_PREFIX="pcebackup" || DMP_PREFIX="pcebackup.$VERSION_BUILD"

[ -z $DBMASTER_FLAG ] && DBMASTER_FLAG="false"
[ -z $RETENTION ] && RETENTION=7

[ -z "$SSHKEY" ] && SSHKEY="$(echo ~)/.ssh/id_rsa"

[[ -z "$BACKUP_TYPE" ]] && usage

if [ $BACKUP_TYPE != "policydb" ] && [ $BACKUP_TYPE != "reportdb" ] && [ $BACKUP_TYPE != "trafficdb" ] && [ $BACKUP_TYPE != "sc_data_dump" ] && [ $BACKUP_TYPE != "all" ]; then
   usage
fi



is_redis_server
IS_REDIS_SERVER=$?
is_db_master
IS_DBMASTER=$?

# return 0 if sc is true
IS_SUPERCLUSTER=$(sudo -u ilo-pce illumio-pce-ctl supercluster-replication-check | grep -c "supercluster PCE.")

if [ $BACKUP_TYPE = "policydb" ] && [ $IS_SUPERCLUSTER -eq 0 ]; then
   echo
   echo "ERROR: Can't run policydb backup on a Supercluster!"
   echo
   exit 1
elif [ $BACKUP_TYPE = "sc_data_dump" ] && [ $IS_SUPERCLUSTER -eq 1 ]; then
   echo
   echo "ERROR: sc_data_dump backup can only be run on Supercluster!"
   echo
   exit 1
fi

if [ $DBMASTER_FLAG = "true" ]; then
   if [ $IS_DBMASTER -gt 0 ]; then
      log_print "INFO" "PCE Version : $VERSION_BUILD" 
      log_print "INFO" "Redis Server: $REDIS_IP"
      log_print "INFO" "Database Node is NOT a master node!"
      log_print "INFO" "Running backup ONLY in master node."

      log_print "INFO" "Cleaning up files older than $RETENTION day(s)"
      find $DUMPDIR/pcebackup.* -mtime +$RETENTION >> $LOGFILE
      find $DUMPDIR/pcebackup.* -mtime +$RETENTION -delete; >> $LOGFILE
      exit 1
   fi
fi

[ $VERSION_BUILD = "" ] && DMP_PREFIX="pcebackup" || DMP_PREFIX="pcebackup.$VERSION_BUILD"
 
[ $IS_DBMASTER -eq 0  ] && DMP_PREFIX_MASTER="$DMP_PREFIX.master" || DMP_PREFIX_MASTER="$DMP_PREFIX"
[ $IS_REDIS_SERVER -eq 0  ] && DMP_PREFIX_MASTER="$DMP_PREFIX_MASTER.redis_server" 

POLICYDB_DMPFILE="$DMP_PREFIX_MASTER.policydb.$HOSTNAME.dbdump.$DTE"

is_db_master "traffic"
IS_DBMASTER=$?
[ $IS_DBMASTER -eq 0  ] && DMP_PREFIX_TRAFFIC="$DMP_PREFIX.master" || DMP_PREFIX_TRAFFIC="$DMP_PREFIX"
TRAFFICDB_DMPFILE="$DMP_PREFIX_TRAFFIC.trafficdb.$HOSTNAME.dbdump.$DTE"

is_db_master "report"
IS_DBMASTER=$?
[ $IS_DBMASTER -eq 0  ] && DMP_PREFIX_REPORT="$DMP_PREFIX.master" || DMP_PREFIX_REPORT="$DMP_PREFIX"
REPORTDB_DMPFILE="$DMP_PREFIX_REPORT.reportdb.$HOSTNAME.dbdump.$DTE"

SC_DMPFILE="$DMP_PREFIX.supercluster-data-dump.$HOSTNAME.dbdump.$DTE"

[ -z $RETENTION ] && RETENTION=7
echo

sudo -u ilo-pce touch "$DUMPDIR/test" 2> /dev/null
if [ $? -eq 0 ]; then
   log_print "INFO" "Starting $PROG Database Backup"
   log_print "INFO" "PCE Version : $VERSION_BUILD" 
   log_print "INFO" "Redis Server: $REDIS_IP"
   is_db_master
   [ $? -eq 0 ] && log_print "INFO" "Data Node is Master Database Node" 

   rm -f $DUMPDIR/test

   if [ $BACKUP_TYPE = "policydb" ] || [ $BACKUP_TYPE = "all" ] && [ $IS_SUPERCLUSTER -eq 1 ]; then
      pce_dbdump $DUMPDIR/$POLICYDB_DMPFILE "policydb"
   fi

   if  [ $BACKUP_TYPE = "sc_data_dump" ] || [ $BACKUP_TYPE = "all" ] && [ $IS_SUPERCLUSTER -eq 0 ]; then
      pce_dbdump $DUMPDIR/$SC_DMPFILE "sc_data_dump"
   fi

   if  [ $BACKUP_TYPE = "trafficdb" ] || [ $BACKUP_TYPE = "all" ]; then
      pce_dbdump $DUMPDIR/$TRAFFICDB_DMPFILE "trafficdb"
   fi

   if  [ $BACKUP_TYPE = "reportdb" ] || [ $BACKUP_TYPE = "all" ]; then
      pce_dbdump $DUMPDIR/$REPORTDB_DMPFILE "reportdb"
   fi

else 
   echo "ERROR: Can't write to directory $DUMPDIR"
   echo "       Check if directory $DUMPDIR has the right permission"
   echo
   exit 1
fi

if [ ! -z $RMTHOST ] && [ ! -z $RMTPATH ] && [ ! -z $RMTUSER ]; then
   if [ $BACKUP_TYPE = "policydb" ] || [ $BACKUP_TYPE = "all" ]; then
      scp_remote_host "$DUMPDIR/$POLICYDB_DMPFILE" $SSHKEY "$RMTUSER" "$RMTHOST" "$RMTPATH"
   fi

   if  [ $BACKUP_TYPE = "trafficdb" ] || [ $BACKUP_TYPE = "all" ]; then
      scp_remote_host "$DUMPDIR/$TRAFFICDB_DMPFILE" $SSHKEY "$RMTUSER" $RMTHOST "$RMTPATH"
   fi

   if  [ $BACKUP_TYPE = "reportdb" ] || [ $BACKUP_TYPE = "all" ]; then
      scp_remote_host "$DUMPDIR/$TRAFFICDB_DMPFILE" $SSHKEY "$RMTUSER" $RMTHOST "$RMTPATH"
   fi

   if  [ $BACKUP_TYPE = "sc_data_dump" ] || [ $BACKUP_TYPE = "all" ]; then
      scp_remote_host "$DUMPDIR/$SC_DMPFILE" $SSHKEY "$RMTUSER" $RMTHOST "$RMTPATH"
   fi
fi

log_print "INFO" "Cleaning up files older than $RETENTION day(s)"
find $DUMPDIR/pcebackup.* -mtime +$RETENTION -print >> $LOGFILE
find $DUMPDIR/pcebackup.* -mtime +$RETENTION -delete; >> $LOGFILE

log_print "INFO" "Completed $PROG Database Backup"
echo





