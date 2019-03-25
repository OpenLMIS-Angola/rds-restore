#!/bin/bash

: ${AWS_ACCESS_KEY_ID:?"Need to set AWS_ACCESS_KEY_ID"}
: ${AWS_SECRET_ACCESS_KEY:?"Need to set AWS_SECRET_ACCESS_KEY"}
: ${REGION:?"Need to set REGION"}
: ${SOURCE_REGION:-$REGION}
: ${SOURCE_INSTANCE:?"Need to set SOURCE_INSTANCE"}
: ${TARGET_INSTANCE:?"Need to set TARGET_INSTANCE"}
: ${MASTER_USER_PASSWORD:?"Need to set MASTER_USER_PASSWORD"}
: ${SECURITY_GROUP:?"Need to set SECURITY_GROUP"}

restore_db_from_snapshot() {
    SNAPSHOT_INSTANCE=$SOURCE_INSTANCE"-snapshot"
    TEMPORARY_INSTANCE=$TARGET_INSTANCE"-backup"

    SNAPSHOT=`aws rds describe-db-snapshots \
        --region $SOURCE_REGION \
        --db-instance-identifier $SOURCE_INSTANCE \
        --query 'DBSnapshots' | \
        jq -r 'max_by(.SnapshotCreateTime).DBSnapshotIdentifier'`
    if [[ $SNAPSHOT = null ]]; then
        echo "Could not find latest snapshot of DB instance $SOURCE_INSTANCE"
        exit
    fi
    echo "Snapshot: $SNAPSHOT"

    DB_CLASS=`aws rds describe-db-instances \
        --region $REGION \
        --db-instance-identifier $TARGET_INSTANCE \
        --query 'DBInstances[*].[DBInstanceClass]' \
        --output text`
    if [[ $DB_CLASS = null ]]; then
        echo "Could not determine DB instance class of $TARGET_INSTANCE"
        exit
    fi
    echo "DB instance class: $DB_CLASS"

    if [[ $REGION != $SOURCE_REGION ]]; then
        echo "Copying snapshot from $SOURCE_REGION to the target region $REGION"

        SNAPSHOT_ARN=`aws rds describe-db-snapshots \
            --region $SOURCE_REGION \
            --db-instance-identifier $SOURCE_INSTANCE \
            --query 'DBSnapshots' | \
            jq -r 'max_by(.SnapshotCreateTime).DBSnapshotArn'`
        echo "Source snapshot ARN: $SNAPSHOT_ARN"

        SNAPSHOT=`echo $SNAPSHOT | sed 's/rds://g'`
        echo "Target snapshot ID: $SNAPSHOT"

        aws rds copy-db-snapshot \
            --region $REGION \
            --source-region $SOURCE_REGION \
            --source-db-snapshot-identifier $SNAPSHOT_ARN \
            --target-db-snapshot-identifier $SNAPSHOT

        wait_available $SNAPSHOT snapshot
    fi

    echo "Restoring snapshot $SNAPSHOT -> $SNAPSHOT_INSTANCE"
    aws rds restore-db-instance-from-db-snapshot \
        --db-instance-class $DB_CLASS \
        --db-instance-identifier $SNAPSHOT_INSTANCE \
        --db-snapshot-identifier $SNAPSHOT \
        --region $REGION

    wait_available $SNAPSHOT_INSTANCE
    echo "Renaming the original database $TARGET_INSTANCE -> $TEMPORARY_INSTANCE"
    aws rds modify-db-instance \
        --region $REGION \
        --db-instance-identifier $TARGET_INSTANCE \
        --new-db-instance-identifier $TEMPORARY_INSTANCE \
        --apply-immediately

    wait_available $TEMPORARY_INSTANCE
    echo "Renaming the recovered database $SNAPSHOT_INSTANCE -> $TARGET_INSTANCE"
    aws rds modify-db-instance \
        --region $REGION \
        --db-instance-identifier $SNAPSHOT_INSTANCE \
        --new-db-instance-identifier $TARGET_INSTANCE \
        --master-user-password $MASTER_USER_PASSWORD \
        --vpc-security-group-ids $SECURITY_GROUP \
        --apply-immediately

    wait_available $TARGET_INSTANCE
    echo "Removing the temporary instance $TEMPORARY_INSTANCE"
    aws rds delete-db-instance \
        --region $REGION \
        --db-instance-identifier $TEMPORARY_INSTANCE \
        --skip-final-snapshot
}

wait_available() {
    ID=${1}
    TYPE=${2:-db}
    SLEEP_TIME=10
    STATUS=none
    while true; do
        if [[ "$TYPE" = "snapshot" ]]; then
            current_status=`aws rds describe-db-snapshots \
                --query 'DBSnapshots[?DBSnapshotIdentifier==\`'${ID}'\`]'.Status \
                --output text \
                --region ${REGION}`
        else
            current_status=`aws rds describe-db-instances \
                --query 'DBInstances[?DBInstanceIdentifier==\`'${ID}'\`]'.DBInstanceStatus \
                --output text \
                --region ${REGION}`
        fi
        if [[ "$current_status" = "$STATUS" ]]; then
            echo -n "."
        else
            if [[ "$STATUS" != "none" ]]; then echo; fi
            echo -n "Status ($TYPE $ID): ${current_status:-none}"
        fi
        if [[ "$current_status" = "available" ]]; then
            echo
            break
        fi
        STATUS=$current_status
        sleep ${SLEEP_TIME}
    done
}

restore_db_from_snapshot

if [ -f "/external/after_restore.sh" ]; then
    sh /external/after_restore.sh
else
    echo "/external/after_restore.sh not found"
fi
