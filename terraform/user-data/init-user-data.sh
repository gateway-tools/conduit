#!/bin/bash

set -x

AWS_DEFAULT_REGION=${region}
AWS_DEFAULT_OUTPUT=json
USER_DATA_BUCKET=${bucket}
SCRIPT_PATH=${path}
SCRIPT_NAME=${filename}

aws s3 cp s3://"$${USER_DATA_BUCKET}"/"$${SCRIPT_PATH}"/"$${SCRIPT_NAME}" .

sudo chmod +x ./"$${SCRIPT_NAME}"

/bin/bash ./"$${SCRIPT_NAME}"
