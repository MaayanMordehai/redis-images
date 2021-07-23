# Initiate Redis and Sentinel

This image is ment to be as initcontainer in a statefulset, it is creating redis and sentinel configuration files.

## Logic

### Standalone

We are reciving redis.conf file and we are adding to it only requirepass parameter as the REDIS_PASSWORD

### Replica

We are reciving redis.conf file and sentinel.conf file and adding to them:
- parameters related to the replica, setting the currect master, quorm and so on.
- parameters to use redis and sentinel with hostnames and not ips (because every time a pod is restarted the ip is changed).
- sentinel id - if we see that current sentinel is known to the other sentinel, setting its id to be the same as it's old id.

We find the info we need by connecting to the other instances - we assume they have the same name and that they are in a statfulset so the pods names should be $NAME-0, $NAME-1 and so on.
If we can't connect to the others we are setting current node as master.

## Environment Variables

| Name              | Default                   | Explain                                                                  						   |
|-------------------|---------------------------|--------------------------------------------------------------------------------------------------------------------------|
| REDIS_PASSWORD    | -                         | The redis password to set                                                						   |
| REPLICAS          | -                         | The number of redis replicas                                             						   |
| SHARED_VOLUME     | /shared                   | Shared location that will be mounted to the sentinel and redis instances, includes logs, scripts and configuration files |
| REDIS_CONF        | -                         | The location the redis.conf to add parameters to is found                                                                |
| SENTINEL_CONF     | -                         | The location the sentine.conf to add parameters to is found                                                              |
| SENTINEL_PASSWORD | -                         | The sentinel password to set                                                                                             |
| NAME              | the name of the container | The name of your redis                                                                                                   |
| REDIS_PORT        | 6379                      | The port to set to redis                                                                                                 |
| SENTINEL_PORT     | 26379                     | The port to set to sentinel                                              						   |


## Pre Stop
The prestop script is supposed to run before redis container (which is persistent) is going down.
It does the following:
- BGSAVE to the redis instance.
- Failover if the current redis instance is master. 
