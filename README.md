# LiveLabs image developing for Developer Days workshops

This repo contains the code to create the "golden master" image for the Developer Days workshops.

This page will ultimately include the steps to update and build a new image when that time comes.

## Agent Memory 26.8 workshop

The new [Agent Memory: Introduction to context and memory engineering lab](ingestion/jl_notebooks/agent_memory_zero_to_hero/README.md)
provides matching student and complete Ollama notebooks for an enterprise
incident-handover assistant, with database-resident embedding/reranking and
a single workshop schema. It uses a separate kernel and opt-in database provisioning;
see its prerequisites before running it on the existing workshop image.

## Python libraries
The list of Python libraries is in requirements.txt with all versions set to static versions where possible, i.e., nothing is set to "latest". This is intended to avoid conflicts and potential problems in the future.

## Adding database objects (tables, indexes, etc.)

This is done by adding or updating shell scripts (yes, they must be shell scripts) to the `ingestion/db-startup` directory. If you are adding a net new `bash` script, you need to add a number as the first part of the filename, as that dictates the order the scripts run in. For example, if you need to create a table (`10-table-create`), you need to load data after that. Therefore, you need to name the file something like `15-data-load`, so it runs after the table creation.

## What software is in this image?

There are three containers created per OCI instance using Podman
1. Oracle 26AI Database (Free)
1. Jupyter Notebook Server
1. Ollama

### Oracle AI Database 26ai (Free)
Since this is the free version, the database is limited to 2GB in total, but 1GB is dedicated to building vector indexes.
