# Infrastructure for Jedi Council secure communication of missions
This is a proposed solution to The Jedi Council: Secrets of the Galaxy

## Requirements
In order to run this test you'll need:
- An AWS account, configured for AWS CLI-compatible access.
- Terraform v1.6.4 (not tested in other versions)

## Building the Infrastructure
1. Clone this git repository.
2. From the project directory, run `~$ terraform apply`

## Testing the secure mission communication
The project directory contains sample `mission` and `manifest` files. In order to test the process, drop these two files in any order in the newly created `jedi-drop` bucket. Each time a file is dropped in that bucket, the lambda function `jedi_lambda` will be triggered. The current mission and manifest will be encrypted and stored in the `jedi-secret` bucket.

If both `mission` and `manifest` have been uploaded, and the ID in the `mission` file exists in the current `manifest`, the location of the objective will be logged. You can watch the output of the lambda in Cloudwatch Live Tail.

If a different `manifest` is uploaded, its contents will be merged with the existing one and stored as current `manifest`, updating already existing IDs. You can test this by renaming the `manifest-extra` to `manifest` and uploading it. A new `mission` always overwrites the previous one.

Before exiting, the lambda function will delete all files from the `jedi-drop` bucket.

## Notes
All the development and testing was done using AWS' free tier.

The code should be improved for consistency and to avoid repetition.

IAM roles and policies should be tightened to improve security (e.g. limiting the use of the KMS key).

