#!/bin/bash

folder () {
  CWD=$(pwd)
  echo "$CWD/$VAULT_NAMESPACE/$(date +%Y_%m_%d_%H%M%S)"
}


# check VAULT_ADDR
if [[ -z "${VAULT_ADDR}" ]]; then
  read -p "VAULT_ADDR value not found. Please enter: " -s VAULT_ADDR
else
  VAULT_ADDR="${VAULT_ADDR}"
fi

# check VAULT_TOKEN
if [[ -z "${VAULT_TOKEN}" ]]; then
  read -p "VAULT_TOKEN value not found. Please enter: " -s VAULT_TOKEN
else
  VAULT_TOKEN="${VAULT_TOKEN}"
fi

# check VAULT_NAMESPACE
if [[ -z "${VAULT_NAMESPACE}" ]]; then
  read -p "VAULT_NAMESPACE value not found. Please enter: " -s VAULT_NAMESPACE
else
  VAULT_NAMESPACE="${VAULT_NAMESPACE}"
fi

# PREPARE VARS
BASE_URL="$VAULT_ADDR/v1/sys/policy"
CURL_OPTIONS="--fail --connect-timeout 3 --retry 1 -s -H X-Vault-Token:$VAULT_TOKEN -H X-Vault-Namespace:$VAULT_NAMESPACE"

# READ AND ITERATE POLICIES
POLICIES=($(curl --request LIST $CURL_OPTIONS $BASE_URL 2>/dev/null | jq  -r ".data.keys | @sh" | tr -d \'))

FOLDER_NAME=$(folder)
if [ ! -d $FOLDER_NAME ]; then
  mkdir -p $FOLDER_NAME;
fi

echo "NAMESPACE: ${VAULT_NAMESPACE}"
echo "POLICIES: ${POLICIES[*]}"
for policy in "${POLICIES[@]}"
do
    echo "Reading policy: $policy, EXECUTING curl $CURL_OPTIONS $BASE_URL/$policy | jq -r \".data.rules | @sh\" | tr -d \'"

    res=$(curl $CURL_OPTIONS $BASE_URL/$policy  | jq -r ".data.rules | @sh" | tr -d \')
    printf '%s%n' "$res" >"$FOLDER_NAME/$policy.hcl"
done