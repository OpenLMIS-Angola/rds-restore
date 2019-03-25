# rds-restore
A script that restores the target RDS instance from the latest snapshot of source instance.

## Usage

In order to use the script, you need the configuration file for it in your local working directory.
In the top-level directory of this repository execute:

```bash
cp sample-config/.env .
```

Then edit the file, so that it contains required credentials and RDS instance ids.

Next simply run the script script using Docker Compose:

```bash
docker-compose run rds-restore
```

That's it - the script will run and give you output about its progress.
