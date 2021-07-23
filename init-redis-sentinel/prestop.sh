#!/bin/bash

#
# This is prestop script
# This script runs when pod goes down
# This does the following
# - BGSAVE - to save the data to the persistent volume
# - if this is the master doing failover
#

MASTER=""

main() {

  if [ -z "$SHARED_VOLUME" ];
  then
    export SHARED_VOLUME=/shared
    echo "SHARED_VOLUME is not defined setting as default value $SHARED_VOLUME"
  fi

  if [ ! -d $SHARED_VOLUME ];
  then
    mkdir -p $SHARED_VOLUME
  else
    echo '' > $SHARED_VOLUME/prestop.log
  fi

  handle_env_vars

  #
  # BGSAVE
  #

  log "INFO: tring to BGSAVE"  
  bgsave_outputash=$(redis-cli -h $HOSTNAME -p $REDIS_PORT --user $REDIS_USER --pass $REDIS_PASSWORD BGSAVE)
  if [ $? -ne 0 ]
  then
    log "ERROR: can't BGSAVE, output: $bgsave_output"
  else
    bgsave_info_output=$(redis-cli -h $HOSTNAME -p $REDIS_PORT --user $REDIS_USER --pass $REDIS_PASSWORD INFO PERSISTENCE)

    until [ $(echo "$bgsave_info_output" | grep rdb_bgsave_in_progress | cut -d':' -f2 | tr -d '\r') -eq 0 ];
    do
      bgsave_info_output=$(redis-cli -h $HOSTNAME -p $REDIS_PORT --user $REDIS_USER --pass $REDIS_PASSWORD INFO PERSISTENCE)
      if [ $? -ne 0 ];
      then
        log "ERROR: could not get the persistence info for the bgsave status, output: $bgsave_info_output"
        break
      fi
      sleep 3
    done

    if [ ! $(echo "sbgsave_info_output" | grep rdb_last_bgsave_status | cut -d":"-f2 | tr -d '\r') = "ok" ];
    then
      log "ERROR: bgsave was not successful"
    else
      log "INFO: BGSAVE completed successfully"
    fi
  fi

  #
  # FAILOVER IF MASTER
  #

  if [$REPLICAS -gt 1 ];
  then
    log "INFO: if I am the master I will initiate failover"
    hosts $(get_hosts $(expr $REPLICAS - 1))
    for host in $hosts
    do
      # getting the master fron sentinel (the master that is defined for this sentinel)
      log "INFO: trying to find current master from $host sentinel"
      master_output=$(timeout 10 redis-cli -h $host -p $SENTINEL_PORT --no-auth-warning -a $SENTINEL_PASSWORD SENTINEL get-master-addr-by-name $NAME)
      if [ $? -ne 0 ];
      then
        log "INFO: could not find master from sentinel on $host:$SENTINEL_PORT"
        log "INFO: this is probably because $host pod is down"
        continue
      fi

      MASTER=$(echo "$master_output" | cut -d',' -f1 | cut -d'"' -f2)

      if [ $MASTER = "NIL" ];
      then
        log "WARNING: Something wrong, found NIL in the sentinel output, I am going to try to find master from other sentinels .."
        MASTER=""
      elif [ "$MASTER" = "$HOSTNAME" ];
      then
        log "INFO: current node is master, doing failover"
        failover_output=$(redis-cli -h $host -p $SENTINEL_PORT --no-auth-warning -a $SENTINEL_PASSWORD SENTINEL failover $NAME)
        if [ $? -ne 0 ];
        then
          log "ERROR: failover command failed, output: $failover_output"
          exit 1
        fi

        until [ ! $(echo $master_output | cut -d',' -f2 | cut -d'"' -f2) = "$HOSTNAME" ];
        do
           master_output=$(redis-cli -h $host -p $SENTINEL_PORT --no-auth-warning -a $SENTINEL_PASSWORD SENTINEL get-master-addr-by-name $NAME)
           if [ $? -ne 0 ];
           then
             log "ERROR: problem getting master after failover from $host:$SENTINEL_PORT"
             exit 1
           fi
           sleep 3
        done

        log "INFO: failover completed"
      else
        log "INFO: current node is not master, failover is not required"
        break
      fi
    done

    if [ -z $MASTER ];
    then
      log "INFO: could not get master, not doing failover"
      exit 1
    fi
  fi
}

# Getting all the hosts in the statefulset
get_hosts() {
  if [ $1 -eq 0 ];
  then
    echo "$NAME-0"
  else
    n=$(expr $1 - 1)
    prev_hosts=$(get_hosts $n)
    echo $prev_hosts" $NAME-$1"
  fi
}

# If var is not defined setting as default
# $l env var
# $2 default value
handle_unmandatory_env_var() {
  if [ -z "$(eval echo \$$1)" ];
  then
    log "INFO: $1 is not defined, setting to default value: $2"
    export $1=$2
  fi
}

# Checking environment variables are valid
handle_env_vars() {
  # handle unmandatory parameters - setting as default if not defined
  handle_unmandatory_env_var REDIS_PORT 6379
  handle_unmandatory_env_var SENTINEL_PORT 26379
  handle_unmandatory_env_var NAME ${HOSTNAME%-*}
  handle_unmandatory_env_var REDIS_USER "default"

  status=0
  for ENV_VAR in REDIS_PASSWORD REPLICAS
  do
    if [ -z "$(eval echo \$$ENV_VAR)" ];
    then
      log "ERROR: $ENV_VAR is undefined"
      status=1
    fi
  done

  if [ ! -z "$REPLICAS" ] && [ $REPLICAS -gt 1 ]
  then
    if [ -z "$SENTINEL_PASSWORD" ]
    then
      log "ERROR: SENTINEL_PASSWORD is undefined"
      status=1
    fi
  fi

  if [ $status -eq 1 ];
  then
    exit 1
  fi
}

# Logging
log() {
  DATE=`date +"%Y-%m-%dT%H:%M:%S"`
  echo $DATE - $@ | tee -a $SHARED_VOLUME/prestop.log
}

main
