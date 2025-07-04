## Database Migrations

This directory contains SQL migration files for the Nim Chat SDK. 

Each migration file should be named in the format `NNN_description.sql`, where `NNN` is a zero-padded number indicating the order of the migration. For example, `001_create_user_table.sql` is the first migration.

## Running Migrations

If you want to install a test sqlite database with tables setup, you can run `nimble migrate` from the command line. This will execute all migration files in order, ensuring that your database schema is up to date.