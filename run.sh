#!/bin/bash

# Fail if LOGGLY_AUTH_TOKEN is not set
if [ -z "$LOGGLY_AUTH_TOKEN" ]; then
  if [ ! -z "$TOKEN" ]; then
    # grandfather old env var
    export LOGGLY_AUTH_TOKEN=$TOKEN
  else
    echo "Missing \$LOGGLY_AUTH_TOKEN"
    exit 1
  fi
fi

# Fail if LOGGLY_TAG is not set
if [ -z "$LOGGLY_TAG" ]; then
  if [ ! -z "$TAG" ]; then
    # grandfather old env var
    export LOGGLY_TAG=$TAG
  else
    echo "Missing \$LOGGLY_TAG"
    exit 1
  fi
fi

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
   action(type=\"omfwd\" protocol=\"__HOST_PROTO__\" target=\"__HOST__\" port=\"__HOST_PORT__\" )
}

"



LOGGLY_LOG_LEVEL=${LOGGLY_LOG_LEVEL:-'warning'}
LOGGLY_LOG_LEVEL_NUMBER=${LOG_LEVEL[${LOGGLY_LOG_LEVEL,,}]}


# Create spool directory
mkdir -p /var/spool/rsyslog


# Expand multiple tags, in the format of tag1:tag2:tag3, into several tag arguments
LOGGLY_TAG=$(echo "$LOGGLY_TAG" | sed 's/:/\\\\" tag=\\\\"/g')

# Replace variables
sed -i "s/LOGGLY_TOKEN/$LOGGLY_AUTH_TOKEN/" /etc/rsyslog.conf
sed -i "s/LOGGLY_TAG/$LOGGLY_TAG/" /etc/rsyslog.conf
sed -i "s/LOGGLY_LOG_LEVEL/$LOGGLY_LOG_LEVEL_NUMBER/" /etc/rsyslog.conf

SYSYLOG_SERVERS=""
while IFS='=' read -r name value ; do
        if [[ $name  == *'_HOST' ]]; then
                prefix=${name%%_*} # delete longest match from back (everything after first _)
                id="$prefix"
                server="${prefix}_HOST"
                SERVER="${!server}"
                server_port="${prefix}_HOSTPORT"
                SERVER_PORT=${!server_port}
                SERVER_PORT=${SERVER_PORT:-514}
                server_proto="${prefix}_HOSTPROTO"
                SERVER_PROTO=${!server_proto}
                SERVER_PROTO=${SERVER_PROTO:-tcp}
                server_loglevel="${prefix}_LOGLEVEL"
                SERVER_LOGLEVEL=${!server_loglevel}
                SERVER_LOGLEVEL="${SERVER_LOGLEVEL:-info}"
                apps="${prefix}_APPS"
                APPS=${!apps}
                if [[ -z ${APPS} ]]; then
                  echo "Please setup R[\d+]_APPS var"
                  exit 1
                fi
                for app in ${APPS}
                do
                  if [[ -z ${FIRST} ]]; then
                    COND="(\$progamname startswith \"${app}\")"
                    FIRST="1"
                  else
                    COND+=" or (\$progamname startswith \"${app}\")"
                  fi
                done
                syslog_server=${SYSYLOG_SERVER_TEMPLATE/__INDEX__/${id}}
                syslog_server=${syslog_server/__HOST__/${SERVER}}
                syslog_server=${syslog_server/__HOST_PROTO__/${SERVER_PROTO}}
                syslog_server=${syslog_server/__HOST_PORT__/${SERVER_PORT}}
                syslog_server=${syslog_server/__CONDITIONS__/${COND}}

                SYSYLOG_SERVERS+=$syslog_server$'\n'

        fi
done < <(env)
IFS= read -d '' -r < <(sed -e ':a' -e '$!{N;ba' -e '}' -e 's/[&/\]/\\&/g; s/\n/\\&/g' <<<"$SYSYLOG_SERVERS") || true
SYSYLOG_SERVERS_REPLACED=${REPLY%$'\n'}
sed -i -r "s/#__SYSLOG_SERVERS__/${SYSYLOG_SERVERS_REPLACED}/g" /etc/rsyslog.conf


# Run RSyslog daemon
exec /usr/sbin/rsyslogd -n