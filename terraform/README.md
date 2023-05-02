# Infrastructure module
## Structure

`user-data` folder contains instance userdata scripts, which will be loaded to a versioned S3 bucket and further used for instance deployment

All other code is segregated by component and/or AWS service (where reasonable). File names are pretty self-explanatory, though there are couple things worth mentioning:

* `data.tf` file contains references to data sources used for convenience and internal data retrieval (e.g. AMI id). Also it contains `locals` block. Component-specific data sources are described in relevant files.

## Requirements

  * Golang 1.18.1 or newer installed
  * Generate IPFS key, ID and secret with `ipfs-key` utility (can be taken from [here](https://github.com/magistersart/ipfs-key), which is a fork of [original repo](https://github.com/whyrusleeping/ipfs-key) plus some minor fixes)
  * a fully set up VPS with private and public subnets
  * two AWS DNS Hosted Zones, one for public usage, one for internal usage
