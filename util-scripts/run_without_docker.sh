#!/bin/sh

# AWS secret access key id and secret
export AWS_ACCESS_KEY_ID=
export AWS_SECRET_ACCESS_KEY=

# AWS region
export REGION=us-east-1

# AWS region of the source instance. Defaults to $REGION.
export SOURCE_REGION=us-east-1

# RDS instance that the snapshot was taken on
export SOURCE_INSTANCE=source-db

# RDS instance on which we restore the snapshot
export TARGET_INSTANCE=target-db

# New master user password
export MASTER_USER_PASSWORD=some-password

# VPC security group id
export SECURITY_GROUP=

./restore_db_from_snapshot.sh
