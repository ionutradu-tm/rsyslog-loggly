#!/bin/bash

# Fail if LOGGLY_AUTH_TOKEN is not set

declare -A LOG_LEVEL=(
[emerg]=0
[alert]=1
[crit]=2
[error]=3
[warning]=4
[notice]=5
[info]=6
[debug]=7
)

SYSYLOG_SERVER_TEMPLATE="
# Setup disk assisted queues. An on-disk queue is created for this action.
# If the remote host is down, messages are spooled to disk and sent when
# it is up again.
\$WorkDirectory /var/spool/rsyslog # where to place spool files
\$ActionQueueFileName fwdRule__INDEX__     # unique name prefix for spool files
\$ActionQueueMaxDiskSpace 1g       # 1gb space limit (use as much as possible)
\$ActionQueueSaveOnShutdown on     # save messages to disk on shutdown
\$ActionQueueType LinkedList       # run asynchronously
\$ActionResumeRetryCount -1        # infinite retries if host is down


if __CONDITIONS__ then {
   action(type=\"omfwd\" protocol=\"__HOST_PROTO__\" target=\"__HOST__\" port=\"__HOST_PORT__\" __TEMPLATE__ )
}

"



LOGGLY_LOG_LEVEL=${LOGGLY_LOG_LEVEL:-'warning'}
LOGGLY_LOG_LEVEL_NUMBER=${LOG_LEVEL[${LOGGLY_LOG_LEVEL,,}]}


# Create spool directory
mkdir -p /var/spool/rsyslog


# Expand multiple tags, in the format of tag1:tag2:tag3, into several tag arguments
LOGGLY_TAG=$(echo "${LOGGLY_TAG}" | sed 's/:/\\\\" tag=\\\\"/g')

# Replace variables

SYSYLOG_SERVERS=""
while IFS='=' read -r name value ; do
        if [[ $name  == *'_HOST' ]]; then
                prefix=${name%%_*} # delete longest match from back (everything after first _)
                id="$prefix"
                server="${prefix}_HOST"
                SERVER="${!server}"
                server_port="${prefix}_HOST_PORT"
                SERVER_PORT=${!server_port}
                SERVER_PORT=${SERVER_PORT:-514}
                server_proto="${prefix}_HOST_PROTO"
                SERVER_PROTO=${!server_proto}
                SERVER_PROTO=${SERVER_PROTO:-tcp}
                server_loglevel="${prefix}_LOG_LEVEL"
                SERVER_LOGLEVEL=${!server_loglevel}
                SERVER_LOGLEVEL="${SERVER_LOGLEVEL:-info}"
                LOG_LEVEL_NUMBER=${LOG_LEVEL[${SERVER_LOGLEVEL,,}]}
                COND_SEVERITY="(\$syslogseverity <= '$LOG_LEVEL_NUMBER')"

                server_logglyenabled="${prefix}_LOGGLY_ENABLED"
                SERVER_LOGGLY_ENABLED=${!server_logglyenabled}
                if [[ ${SERVER_LOGGLY_ENABLED,,} == "yes" ]];then
                  server_loggly_tag="${prefix}_LOGGLY_TAG"
                  SERVER_LOGGLY_TAG=${!server_loggly_tag}
                  if [[ -z "${SERVER_LOGGLY_TAG}" ]];then
                    echo "Please provie LOGGLY TAG"
                    exit 1
                  fi
                  server_loggly_token="${prefix}_LOGGLY_TOKEN"
                  SERVER_LOGGLY_TOKEN=${!server_loggly_token}
                  if [[ -z "${SERVER_LOGGLY_TOKEN}" ]];then
                    echo "Please provie LOGGLY TAG"
                    exit 1
                  fi
                  TEMPLATE="template=\"LogglyFormat\""
                  sed -i "s/LOGGLY_TOKEN/${SERVER_LOGGLY_TOKEN}/" /etc/rsyslog.conf
                  sed -i "s/LOGGLY_TAG/${SERVER_LOGGLY_TAG}/" /etc/rsyslog.conf
                fi
                apps="${prefix}_APPS"
                APPS=${!apps}
                COND=""
                if [[ -n ${APPS} ]]; then
                  for app in ${APPS}
                  do
                    COND+="(\$programname startswith '${app}') or "
                  done
                  COND="("${COND}
                  COND=$(echo $COND| sed 's/\(.*\)\ or/\1\) and /')
                fi
                COND=${COND}${COND_SEVERITY}
                syslog_server=${SYSYLOG_SERVER_TEMPLATE/__INDEX__/${id}}
                syslog_server=${syslog_server/__HOST__/${SERVER}}
                syslog_server=${syslog_server/__HOST_PROTO__/${SERVER_PROTO}}
                syslog_server=${syslog_server/__HOST_PORT__/${SERVER_PORT}}
                syslog_server=${syslog_server/__CONDITIONS__/${COND}}
                syslog_server=${syslog_server/__TEMPLATE__/${TEMPLATE}}

                SYSYLOG_SERVERS+=$syslog_server$'\n'

        fi
done < <(env)

IFS= read -d '' -r < <(sed -e ':a' -e '$!{N;ba' -e '}' -e 's/[&/\]/\\&/g; s/\n/\\&/g' <<<"$SYSYLOG_SERVERS") || true
SYSYLOG_SERVERS_REPLACED=${REPLY%$'\n'}
sed -i -r "s/#__SYSLOG_SERVERS__/${SYSYLOG_SERVERS_REPLACED}/g" /etc/rsyslog.conf


# Run RSyslog daemon
exec /usr/sbin/rsyslogd -n