# Initiate Redis and Sentinel

This image is ment to be as initcontainer in a statefulset, it is creating redis and sentinel configuration files.

## Logic

### Standalone

We are reciving redis.conf file and we are adding to it only requirepass parameter as the REDIS_PASSWORD

### Replica

We are reciving redis.conf file and sentinel.conf file and adding to them:
- parameters related to the replica, setting the currect master (if master was not found current node will be master), setting quorm and so on.
- parameters to use redis and sentinel with hostnames and not ips (because every time a pod is restarted the ip is changed).
- sentinel id - if we see that current sentinel is known to the other sentinel, setting its id to be the same as it's old id.

## Environment Variables

| Name | Default | Explain |
|---|---|---|
| REDIS_PASSWORD | - | The redis password to set |
| REPLICAS | - | The number of redis replicas |
| CONFIGURATION_VOLUME | /configurations | The location of the log and the configuration files this image creating |
| REDIS_CONF | - | The location the redis.conf to add parameters to is found |
| SENTINEL_CONF | - | The location the sentine.conf to add parameters to is found |
| SENTINEL_PASSWORD | - | The sentinel password to set |
| NAME | the name of the container | The name of your redis |
| REDIS_PORT | 6379 | The port to set to redis |
| SENTINEL_PORT | 26379 | The port to set to sentinel |

