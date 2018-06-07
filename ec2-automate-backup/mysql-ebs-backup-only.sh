#!/usr/bin/env bash

## This line below when it has -k and -s flags -- the process purges snapshots before taking new ones.
## That means there is no tie back to the original instances/volumes
## sh -x ./ec2-automate-backup/ec2-automate-backup.sh -k 10 purge_snapshots=false -n -s tag -t "Backup-Daily=true" && echo success || echo failed;

# Test by volume
# ./ec2-automate-backup/ec2-automate-backup.sh -n -v vol-057f9136fd57d3056

# This ONLY snapshots
# sh ec2-automate-backup/ec2-automate-backup.sh -n -s tag -t Backup-Daily,Values=true

#!/bin/bash

set -e
set -o pipefail

function bye() {
    local message=${1:-"Bye!"}
    echo ${message}
    exit 1
}

aws ec2 describe-instances --output text --filters 'Name=tag:Name,Values=*mysql*' 'Name=instance-state-name,Values=running' --query 'Reservations[*].Instances[*].[InstanceId, [Tags[?Key==`dns_aname`].Value] [0][0]]' | grep -v "None" > mysql_instance_list_dns.txt

aws ec2 describe-volumes --region us-east-1 --filters Name=tag:Backup-Daily,Values=true  --query 'Volumes[*].Attachments[*].[InstanceId,VolumeId]' > all_instances_vols.txt

mysql_ebs_vols=$(for instance in `cat mysql_instance_list_dns.txt | awk '{print $1}'`; do  grep $instance all_instances_vols.txt | awk '{print $2}'; done)

for instance in `cat  mysql_instance_list_dns.txt | awk '{print $1}'`;
do
if grep -q ${instance} all_instances_vols.txt ; then
    echo found
    grep $instance all_instances_vols.txt | awk '{print $2}' >> output.txt
else
    echo not found
fi
done

# Test to see if only the purge occurs
# sh ec2-automate-backup/ec2-automate-backup.sh -k 10 -p -n -s tag -t Backup-Daily,Values=true

sh ec2-automate-backup/ec2-automate-backup.sh -k 10 -p -n -v ${mysql_ebs_vols}
