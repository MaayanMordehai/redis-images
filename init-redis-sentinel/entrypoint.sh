#!/bin/bash

#
# This is an init container entrypoint.
# configure redis and sentinel to work currectly togther :)
#
# This entrypoint is setting the configuration currectly when redis and sentinel 
# running on the same pod, in a statefulset, with the same ports for the nodes.
# Was not tested for a diffrent case.
#
# Also this entrypoint take existing redis.conf and sentinel.conf and only added it's parameters to it
# 
# This script is:
# - when standalone/replica
#   - configuring redis requirepass
# - when replica:
#   - configuring redis and sentinel to work with hostnames
#   - configuring redis and sentinel with the currect master
#   - configuring sentinel with the currect sentinel id (if the pod restarted we need the same sentinel id)
#


MASTER=""
MYID=""

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
    echo '' > $SHARED_VOLUME/init.log
  fi

  echo "logfile is in $SHARED_VOLUME/init.log"

  # Environment variables handling
  handle_env_vars

  export REDIS_PARAMETERS=${SHARED_VOLUME}/redis.conf

  # coping the parameters configurations to an editable location, configuration volume
  cp $REDIS_CONF $REDIS_PARAMETERS 2>&1 | tee -a $SHARED_VOLUME/init.log

  if [ $? -ne 0 ];
  then
    log "ERROR: could not get redis.conf file"
    exit 1
  fi

  sed -i '/^requirepass /d' $REDIS_PARAMETERS 2>&1 | tee -a $SHARED_VOLUME/init.log
  echo "requirepass $REDIS_PASSWORD" >> $REDIS_PARAMETERS

  if [ $REPLICAS -eq 1 ];
  then
    log "INFO: done setting configurations for standalone redis"
    exit 0
  fi

  export SENTINEL_PARAMETERS=${SHARED_VOLUME}/sentinel.conf

  export REPLICAS_CONNECTED_TO_PRIM=$(expr $REPLICAS / 2) 
  export QUORUM_SIZE=$(expr $REPLICAS_CONNECTED_TO_PRIM + 1)

  # coping the parameters configurations to an editable location - configuration volume
  cp $SENTINEL_CONF $SENTINEL_PARAMETERS 2>&1 | tee -a $SHARED_VOLUME/init.log

  if [ $? -ne 0 ];
  then
    log "ERROR: could not get configmap sentinel.conf file"
    exit 1
  fi

  # setting vars for the redis.conf
  sed -i '/^masterauth /d' $REDIS_PARAMETERS 2>&1 | tee -a $SHARED_VOLUME/init.log
  echo "masterauth $REDIS_PASSWORD" >> $REDIS_PARAMETERS
  sed -i '/^min-replicas-to-write /d' $REDIS_PARAMETERS 2>&1 | tee -a $SHARED_VOLUME/init.log
  echo "min-replicas-to-write $REPLICAS_CONNECTED_TO_PRIM" >> $REDIS_PARAMETERS
  sed -i '/^replica-announce-ip /d' $REDIS_PARAMETERS 2>&1 | tee -a $SHARED_VOLUME/init.log
  echo "replica-announce-ip $HOSTNAME" >> $REDIS_PARAMETERS
  sed -i '/^replica-announce-port /d' $REDIS_PARAMETERS 2>&1 | tee -a $SHARED_VOLUME/init.log
  echo "replica-announce-port $REDIS_PORT" >> $REDIS_PARAMETERS

  # getting the master from sentinels
  get_master $REPLICAS
  if [ -z "$MASTER" ] || [ "$MASTER" = "$HOSTNAME"];
  then
    log "INFO: setting current node $HOSTNAME as master"
    MASTER=$HOSTNAME
  else
    log "INFO: setting $MASTER as master"
    sed -i '/^slaveof /d' $REDIS_PARAMETERS 2>&1 | tee -a $SHARED_VOLUME/init.log
    sed -i '/^replicaof /d' $REDIS_PARAMETERS 2>&1 | tee -a $SHARED_VOLUME/init.log
    echo "replicaof $MASTER $REDIS_PORT" >> $REDIS_PARAMETERS
  fi

  # making sentinel use the service name and not ip on the port the user asked
  sed -i '/^port /d' $SENTINEL_PARAMETERS 2>&1 | tee -a $SHARED_VOLUME/init.log
  echo "port $SENTINEL_PORT" >> $SENTINEL_PARAMETERS
  sed -i '/^requirepass /d' $SENTINEL_PARAMETERS 2>&1 | tee -a $SHARED_VOLUME/init.log
  echo "requirepass $SENTINEL_PASSWORD" >> $SENTINEL_PARAMETERS
  sed -i '/^sentinel resolve-hostnames /d' $SENTINEL_PARAMETERS 2>&1 | tee -a $SHARED_VOLUME/init.log
  echo "sentinel resolve-hostnames yes" >> $SENTINEL_PARAMETERS
  sed -i '/^sentinel announce-hostnames /d' $SENTINEL_PARAMETERS 2>&1 | tee -a $SHARED_VOLUME/init.log
  echo "sentinel announce-hostnames yes" >> $SENTINEL_PARAMETERS
  sed -i '/^sentinel announce-ip /d' $SENTINEL_PARAMETERS 2>&1 | tee -a $SHARED_VOLUME/init.log
  echo "sentinel announce-ip $HOSTNAME" >> $SENTINEL_PARAMETERS
  sed -i '/^sentinel announce-port /d' $SENTINEL_PARAMETERS 2>&1 | tee -a $SHARED_VOLUME/init.log
  echo "sentinel announce-port $SENTINEL_PORT" >> $SENTINEL_PARAMETERS
  # defining the master
  echo "sentinel monitor $NAME $MASTER $REDIS_PORT $QUORUM_SIZE" >> $SENTINEL_PARAMETERS
  echo "sentinel auth-pass $NAME $REDIS_PASSWORD" >> $SENTINEL_PARAMETERS

  get_my_sentinel_id $REPLICAS

  if [ ! -z "$MYID" ]
  then
    sed -i '/^sentinel myid /d' $SENTINEL_PARAMETERS 2>&1 | tee -a $SHARED_VOLUME/init.log
    echo "sentinel myid $MYID" >> $SENTINEL_PARAMETERS
  else
    log "INFO: could not find my sentinel id, so will let new one to be generated"
  fi

  log "INFO: done configuring configurations for current redis and sentinel nodes"
}

##############################################
# Getting the master redis to MASTER variable
# $1 - NUMBER OF REPLICAS
# Returning:
# MASTER - The current master
# ############################################
get_master() {

  # Checking sentinel nodes for master
  MASTER=""
  hosts=$(get_hosts $(expr $1 - 1))
  for host in $hosts
  do
    # current host sentinel is not up so no need to check it ..
    if [ "$host" = "$HOSTNAME" ];
    then
      continue
    fi

    # getting the master from sentinel (the master that is defined for this sentinel)
    log "INFO: trying to find current master from $host sentinel...."
    master_output=$(timeout 10 redis-cli -h $host -p $SENTINEL_PORT --no-auth-warning -a $SENTINEL_PASSWORD SENTINEL get-master-addr-by-name $NAME)

    if [ $? -ne 0 ];
    then
      log "INFO: could not find master from sentinel on $host:$SENTINEL_PORT"
      log "INFO: this is probably because $host pod is down"
      continue
    fi

    MASTER=$(echo $master_output | awk '{ print $1 }')

    if [ "$MASTER" = "NIL" ] || [ ! ${MASTER##*-} -lt $REPLICAS ];
    then
      log "WARNING: Something wrong, found $MASTER in the sentinel output, I am going to try to find master from other sentinels .."
      MASTER=""
    else
      break
    fi

  done
}


# Finding from other sentinels this sentinel id
# If this is not the first time this pod is going up.
# other sentinels may remember it, so it needs to go up with same sentinel id
get_my_sentinel_id() {

  MYID=""
  
  hosts=$(get_hosts $(expr $1 - 1))
  for host in $hosts
  do
    # current host sentinel is not up so no need to check it ..
    if [ "$host" = "$HOSTNAME" ];
    then
      continue
    fi

    sentinels_know_output=$(timeout 10 redis-cli -h $host --no-auth-warning -p $SENTINEL_PORT -a $SENTINEL_PASSWORD sentinel sentinels $NAME)
    if [ $? -ne 0 ];
    then
      log "INFO: could not find other sentinels from sentinel on $host:$SENTINEL_PORT"
      log "INFO: this is probably because $host pod is down"
      continue
    fi

    if [ ! -z $(echo "$sentinels_know_output" | egrep -A 1 'ip|runid' | egrep -v 'ip|runid|--' | grep $HOSTNAME) ];
    then
      MYID=$(echo "$sentinels_know_output" | egrep -A 1 'ip|runid' | egrep -v 'ip|runid|--' | grep -A 1 $HOSTNANE | tail -n 1)
      log "INFO: found my id: $MYID from the other sentinels configurations"
      break
    fi
  done
}

# Getting all the hosts in the statefulset
get_hosts() {
  if [ $1 -eq 0 ];
  then
    echo "$NAME-0"
  else
    n=$(expr $1 - 1)
    prev_hosts=$(get_hosts $n)
    echo $prev_hosts $NAME-$1
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

  status=0
  for ENV_VAR in REDIS_CONF REDIS_PASSWORD REPLICAS
  do
    if [ -z "$(eval echo \$$ENV_VAR)" ];
    then
      log "ERROR: $ENV_VAR is undefined"
      status=1
    fi
  done

  if [ ! -z "$REPLICAS" ] && [ $REPLICAS -gt 1 ]
  then
    if [ -z "$SENTINEL_CONF" ] || [ -z "$SENTINEL_PASSWORD" ]
    then
      log "ERROR: SENTINEL_CONF or SENTINEL_PASSWORD is undefined"
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
  echo $DATE - $@ | tee -a $SHARED_VOLUME/init.log
}

main

