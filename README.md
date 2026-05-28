# LiveLabs image developing for Developer Days workshops

This repo contains the code to create the "golden master" image for the developer days workshops.

This page will ultimately include the steps to update and build a new image when that time comes needed.

## Python libraries
The list of python libraries is in requirements.txt with all versions at a static version, i.e. nothing is set to "latest". This is to avoid conflicts and potential problems in the future.

## Adding database objects (tables, indexes, etc.)

This is done by adding or updating shell scripts (yes, they must be shell scripts) to the `ingestion/db-startup` directory. If you are adding a net new `bash` script, you need to add a number as the first part of the filename as that dictates the order the scripts run in. For example, if you need to create a table (`10-table-create`) and load data (`15-data-load`) the data load script must be run after the table create.

## What software is in this image?

There are four containers created per OCI instance using Podman
1. Oracle 26AI Database (Free)
1. Jupyter Notebook Server
1. Oracle Private AI container
1. Ollama

### Oracle 26AI Database (Free)
Since this is the free version, the database is limited to 2GB in total, but 1GB is dedicated to building vector indexes.

### Jupyter Notebook Server

### Oracle Private AI container

### Ollama