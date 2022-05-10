#!/usr/bin/env bash
# Script uses CLI: `jq` & `curl`.

#
# Script Name: migrate-secrets.sh
#
# Author: Miroslav
# Date : 2022/05/05
#
# Description: Script helps you migrate or copy Vault secrets 
#
# Run Information: Using .env file, update your data and start script "bash migrate-secrets.sh"
#
# Error Log: Any errors or output associated with the script can be found in /logs
#

ticker () {
  echo "$(date +%Y_%m_%d_%H%M%S)"
}

# =========================================
if [ -f .env ]; then
  export $(echo $(cat .env | sed 's/#.*//g'| xargs) | envsubst)
fi

TOTAL_READ=0
TOTAL_READ_EX=0
TOTAL_WRITE=0
TOTAL_WRITE_EX=0
TOTAL_TRAVEL=0
DELETE_SECRETS="${DELETE_DESTINATION_SECRET:-0}"

echo >> ./logs/log.txt
echo "Start $(ticker)" >> ./logs/log.txt

# =========================================
# check V1_ADDR
if [[ -z "${V1_ADDR}" ]]; then
  read -rp "V1_ADDR value not found. Please enter: " V1_ADDR
fi

# check VAULT_TOKEN
if [[ -z "${V1_TOKEN}" ]]; then
  read -rsp "V1_TOKEN value not found. Please enter: " V1_TOKEN
  echo
fi

# check VAULT_NAMESPACE
if [[ -z "${V1_NAMESPACE}" ]]; then
  read -rp "V1_NAMESPACE value not found. Please enter: " V1_NAMESPACE
fi

# check SOURCE ENGINE
if [[ -z "${V1_KV}" ]]; then
  read -rp  "V1_KV value not found. Please enter (with trailing slash): " V1_KV
fi

# check V2_ADDR
if [[ -z "${V2_ADDR}" ]]; then
  read -rp "V2_ADDR value not found. Please enter: " V2_ADDR
fi

# DESTINATION check VAULT_TOKEN
if [[ -z "${V2_TOKEN}" ]]; then
  read -rsp "Destination V2_TOKEN value not found. Please enter: " V2_TOKEN
  echo
fi

# check VAULT_NAMESPACE
if [[ -z "${V2_NAMESPACE}" ]]; then
  read -rp "V2_NAMESPACE value not found. Please enter: " V2_NAMESPACE
fi

# check DESTINATION PATH
if [[ -z "${V2_KV}" ]]; then
  read -rp "V2_KV value not found. Please enter (with trailing slash): " -s V2_KV
fi

# VERIFY ENV DATA
if [[ -n "${V2_BASE_PATH}" ]] && ! [[ ${V2_BASE_PATH: -1} == '/' ]]; then
  echo "V2_BASE_PATH variable must end with /"
  exit
fi

# VERIFY ENV DATA
if [[ -n "${V1_BASE_PATH}" ]] && ! [[ ${V1_BASE_PATH: -1} == '/' ]]; then
  echo "V1_BASE_PATH variable must end with /"
  exit
fi

CURL_SOURCE_OPTIONS="--fail --connect-timeout 3 --retry 1 -s -H X-Vault-Token:$V1_TOKEN -H X-Vault-Namespace:$V1_NAMESPACE"
CURL_DEST_OPTIONS="--fail --connect-timeout 3 --retry 1 -s -H X-Vault-Token:$V2_TOKEN -H X-Vault-Namespace:$V2_NAMESPACE"

export VAULT_TOKEN=${V1_TOKEN} && export VAULT_ADDR=${V1_ADDR} && export VAULT_NAMESPACE=${V1_NAMESPACE};
# // ^^ for convenience with Vault CLI and V2 values for API / curl

echo "Checking KV engine version"

# // check KV version 1 or 2 for source & destination so as to append 'data/' to path.
V2_KV_VER=$(curl $CURL_DEST_OPTIONS ${V2_ADDR}/v1/sys/mounts 2>/dev/null | jq -r ".[\"${V2_KV}\"]|.options.version") ;

# check is destination engine enabled
if [[ ${V2_KV_VER} == null ]] ; then 
  echo "Check if $V2_KV is enabled on destination address" ; 
  exit 1; 
fi ;

if [[ ${V2_KV_VER} == "2" ]] ; then V2_KV_DATA="${V2_KV}data" ; fi ;

# (engine, path = '', item = '', level = 0):
# $1 - engine
# $2 - path
# $3 - item
# $4 - level

function traverse_path()
{
  local V1_KV_LIST=() ;
  local engine=${1:-""} ;
  local item=${2:-""} ;
  local level=${3:-1} ;
  local path=${4:-""} ;

  ((TOTAL_TRAVEL++))
  prespace=$(printf "%*s%s" $level '')
  local FULL_PATH=$V1_BASE_PATH$path$item

  echo "${prespace}Traversing level $level $engine$FULL_PATH" # >> log.txt

  V1_KV_LIST=($(curl -X LIST $CURL_SOURCE_OPTIONS ${V1_ADDR}/v1/${engine}metadata/$FULL_PATH 2>/dev/null | jq  -r ".data.keys | @sh" | tr -d \'))

  # if engine empty
  # if ! (( V1_KV_LIST != null )); then
  #   echo "KV Path is emtpy ${engine}$FULL_PATH"; 
  # fi

  for key in "${V1_KV_LIST[@]}" ; do
    
    local FULL_META_PATH="${V2_ADDR}/v1/${V2_KV}metadata/$V2_BASE_PATH$FULL_PATH${key}"

    if [[ ${key} == *'/' ]] ; then traverse_path "$engine" "${key}" "$((level+1))" "$FULL_PATH" ;
    else
      prespace=$(printf "%*s" $((level+2)) '')

      # delete destination secret
      if [ "$DELETE_SECRETS" == 1 ]; then
        echo "${prespace}Deleting destination secret $FULL_META_PATH"
        sRESP=$(curl -k -L -X DELETE -H "X-Vault-Token: ${V2_TOKEN}" -H "X-Vault-Namespace: ${V2_NAMESPACE}" \
          -o /dev/null -s -w "%{http_code}\n" "$FULL_META_PATH") ;
      fi 

      if [ "$MIGRATE_SECRETS_VERSIONS" == 1 ]; then
        # read secret metadata
        KV_META=($(curl $CURL_SOURCE_OPTIONS ${V1_ADDR}/v1/${V1_KV}metadata/$FULL_PATH${key} 2>/dev/null | jq '.data.versions | [keys[] | tonumber] | sort' | tr -d '[]," '))

        ((TOTAL_READ++))

        DESTINATION_PATH="${V2_ADDR}/v1/${V2_KV_DATA}/$V2_BASE_PATH$FULL_PATH${key}"
        printf "%s INFO => Engine: %s, Path: %s => %s\n" "$prespace" "${V1_KV}" "$FULL_PATH${key}" "$DESTINATION_PATH"
        printf "%s INFO => Engine: %s, Path: %s => %s\n" "$prespace" "${V1_KV}" "$FULL_PATH${key}" "$DESTINATION_PATH" >> ./logs/log.txt;

        echo -n "$prespace CP Versions: "
        for version in "${KV_META[@]}"
        do
          KV_DATA=$(curl $CURL_SOURCE_OPTIONS ${V1_ADDR}/v1/${V1_KV}data/$FULL_PATH${key} 2>/dev/null | jq -r '.data.data')
          ((TOTAL_READ_EX++))

          # // strip or add 'data' object subject to kv1 or kv2
          if [[ ${V2_KV_VER} == "2" && "$(echo ${KV_DATA} | jq '.data')" == "null" ]] ; then
            KV_DATA="{ \"data\": ${KV_DATA}}" ;
          fi ;
          if [[ ${V2_KV_VER} == "1" && ! "$(echo ${KV_DATA} | jq '.data')" == "null" ]] ; then
            KV_DATA=$(echo "${KV_DATA}" | jq '.data') ;
          fi ; 

          # // re-write to new Vault / KV engine
          echo -n "v$version "
          sRESP=$(curl -k -L -X POST -H "X-Vault-Token: ${V2_TOKEN}" -H "X-Vault-Namespace: ${V2_NAMESPACE}" -d "${KV_DATA}" \
            -o /dev/null -s -w "%{http_code}\n" "$DESTINATION_PATH") ;

          if ! [[ ${sRESP} == "200" || ${sRESP} == "204" ]]; then 
            printf "%s CPP => Engine: %s, Path: %s => %s\n" "$prespace" "${V1_KV}" "$FULL_PATH${key}" "$DESTINATION_PATH"
            printf "%s ERROR (%s): CP: %s to %s\n" "$prespace" "$sRESP" "${V1_KV}$FULL_PATH${key}" "$DESTINATION_PATH" ;
          elif [[ ${sRESP} == "200" ]]; then
            ((TOTAL_WRITE_EX++))
          fi ;
        done
      else
        DESTINATION_PATH="${V2_ADDR}/v1/${V2_KV_DATA}/$V2_BASE_PATH$FULL_PATH${key}"
        printf "%s INFO => Engine: %s, Path: %s => %s\n" "$prespace" "${V1_KV}" "$FULL_PATH${key}" "$DESTINATION_PATH"
        printf "%s INFO => Engine: %s, Path: %s => %s\n" "$prespace" "${V1_KV}" "$FULL_PATH${key}" "$DESTINATION_PATH" >> ./logs/log.txt;

        KV_DATA=$(curl $CURL_SOURCE_OPTIONS ${V1_ADDR}/v1/${V1_KV}data/$FULL_PATH${key} 2>/dev/null | jq -r '.data.data')
        ((TOTAL_READ++))
        ((TOTAL_READ_EX++))

        # // strip or add 'data' object subject to kv1 or kv2
        if [[ ${V2_KV_VER} == "2" && "$(echo ${KV_DATA} | jq '.data')" == "null" ]] ; then
          KV_DATA="{ \"data\": ${KV_DATA}}" ;
        fi ;
        if [[ ${V2_KV_VER} == "1" && ! "$(echo ${KV_DATA} | jq '.data')" == "null" ]] ; then
          KV_DATA=$(echo "${KV_DATA}" | jq '.data') ;
        fi ; 

        # // re-write to new Vault / KV engine
        sRESP=$(curl -k -L -X POST -H "X-Vault-Token: ${V2_TOKEN}" -H "X-Vault-Namespace: ${V2_NAMESPACE}" -d "${KV_DATA}" \
        -o /dev/null -s -w "%{http_code}\n" "$DESTINATION_PATH") ;

        if ! [[ ${sRESP} == "200" || ${sRESP} == "204" ]]; then 
          printf "%s CPP => Engine: %s, Path: %s => %s\n" "$prespace" "${V1_KV}" "$FULL_PATH${key}" "$DESTINATION_PATH"
          printf "%s ERROR (%s): CP: %s to %s\n" "$prespace" "$sRESP" "${V1_KV}$FULL_PATH${key}" "$DESTINATION_PATH" ;
        elif [[ ${sRESP} == "200" ]]; then
          
          ((TOTAL_WRITE_EX++))

        fi ;
      fi
      echo 
    fi ;
  done ;
}

traverse_path "${V1_KV}"

echo "Done! Total Secrets Read: $TOTAL_READ, Total Versions: $TOTAL_READ_EX, Total Write: $TOTAL_WRITE_EX, Total Travel: $TOTAL_TRAVEL"
