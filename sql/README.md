# SQL init templates

This directory stores non-destructive database initialization SQL templates for DTM.

The installer renders these templates and runs them through a Kubernetes Job when `--store-driver` is `mysql` or `postgres`.
