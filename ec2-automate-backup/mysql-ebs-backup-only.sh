#!/bin/bash

##
## Setting checks for executables that should be in path -- fail if not
##

## set -e
set -o pipefail

function bye() {
    local message=${1:-"Bye!"}
    echo ${message}
    exit 1
}

type -P aws &> /dev/null || bye "aws cli not found on PATH"
type -P date &> /dev/null || bye "date not found on PATH"
type -P sort &> /dev/null || bye "sort not found on PATH"
type -P cat &> /dev/null || bye "cat not found on PATH"
type -P grep &> /dev/null || bye "grep not found on PATH"
type -P awk &> /dev/null || bye "awk not found on PATH"

##  Context on aws-missing-tools
##  Great repo - not updated for the last 3 years so drift in aws cli tag naming conventions
##  This tool repo is forked under PP Github repo and updated for tagging conventions
##  It now outputs additional information in JSON for lookup at this point

## Examples of ec2-automate-backup.sh script :
## The backup of entire list of volumes with purge first snaps second
## sh ec2-automate-backup/ec2-automate-backup.sh -k 10 -p -n -s tag -t Backup-Daily,Values=true

## Test by volume
## ./ec2-automate-backup/ec2-automate-backup.sh -n -v vol-057f9136fd57d3056

## This ONLY snapshots
## sh ec2-automate-backup/ec2-automate-backup.sh -n -s tag -t Backup-Daily,Values=true

##  ##################################################################################################################
## This script
## Scope:  The original Nagios crontab job was all or nothing and there was a need to stagger out the MySQL snaps
##          outside of doing an all or nothing
## The original script with the flags -k 10 -p -n -s tag -t Backup-Daily,Values=true does the following
##  1st runs the purge of any backup 10 days old based on the tag on the volume of Backup-Daily=true
##  2nd snapshots the same volumes to obtain a recent backup and populates the tags for use in future purges
##    "Key": "PurgeAfterFE"
##    "Key": "PurgeAllow"
##  ##################################################################################################################
##  The first step is to get the list of mysql instances regardless of volume tags
##  The second step is to get the list of volumes that have Backup-Daily = true and get their instance id and volume id
##  The third step is to then populate the variable ${mysql_ebs_vols} for mysql volumes based on knowing
##      that the logic of grep only works on the instances in the mysql dns list that also have volumes with tags
##  The fourth step is to issue the ec2-automate-backup.sh script to back up those volumes

##  WIP goals are to add the logic of finding out if the snapshots completed and what time they started/ended
##  ##################################################################################################################

echo "-- Obtaining the mysql instance list with instance_id and dns_aname tag  ------------------------------------------"
aws ec2 describe-instances --output text --filters 'Name=tag:Name,Values=*mysql*' 'Name=instance-state-name,Values=running' --query 'Reservations[*].Instances[*].[InstanceId, [Tags[?Key==`dns_aname`].Value] [0][0]]' | grep -v "None" > mysql_instance_list_dns.txt

cat mysql_instance_list_dns.txt

echo "-- Obtaining the entire EBS volume list that has tags Backup-Daily = true -----------------------------------------"
aws ec2 describe-volumes --output text --region us-east-1 --filters Name=tag:Backup-Daily,Values=true  --query 'Volumes[*].Attachments[*].[InstanceId,VolumeId]' > all_instances_vols.txt

cat all_instances_vols.txt

for instance in `cat  mysql_instance_list_dns.txt | awk '{print $1}'`;
do
if grep -q ${instance} all_instances_vols.txt ; then
    echo "-- Volume found for MySQL DB instance ${instance}  ---------------------------------------------------------------"
    grep $instance all_instances_vols.txt | awk '{print $2}' >> mysql_ebs_vols.txt
else
    echo "-- This MySQL DB ${instance} does not have any snapshots being taken - Is this desired state? --------------------"
    echo " $? is the Shell return code for ${instance} not found to have Backup-Daily = true tags on any volumes "
fi
done

cat mysql_ebs_vols.txt

mysql_ebs_vols=`cat mysql_ebs_vols.txt`
echo "-- The MySQL volume list to snapshot is : ${mysql_ebs_vols} -------------------------------------------------------"

echo "-- Issuing the EBS snapshots of MySQL volumes set with tag Backup-Daily = true ------------------------------------"
sh ec2-automate-backup/ec2-automate-backup.sh -k 10 -p -n -v ${mysql_ebs_vols}
