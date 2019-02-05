#!/usr/bin/env bash

#we load the mirror specific settings from the config
#provided as the first argument

if [[ ! -e ${1} ]];then
    # the provided config file does not exist
    # perhaps this should send an email insted
    echo "Error in dotsrc-sync.bash: provided config file does not exist: ${1}" > ${HOME}/sync-error.log
    exit -1
fi

source ${1}

if [[ -z ${NAME} ]];then
    echo "Error in dotsrc-sync.bash: NAME is not set, file sourced: ${1}" > ${HOME}/sync-error.log
    exit -1
fi

DEBUG=${2}
DEFAULTRSYNCCMD="/usr/bin/rsync --recursive --force --links --safe-links --hard-links --times --perms --sparse --stats --delete --verbose --timeout=60"
LOGDIR="${HOME}/log/${NAME}"
LOGCMD="${LOGDIR}/${NAME}-$(date +%Y-%m-%d-%H%M).log"
LOCK="${HOME}/locks/${NAME}"

debug(){
    if [[ ! -z ${DEBUG} ]];then
	echo ${1}
    fi
}
#if a mirror need to override the default rsync cmd
#it just sets RSYNCCMD in the config
if [[ ! -z ${RSYNCCMD} ]];then
    debug "RSYNCCMD set in config file to: ${RSYNCCMD}"
else
    debug "Using default rsync command"
    RSYNCCMD=${DEFAULTRSYNCCMD}
fi

# Make it possible to override local dir
if [[ ! -z ${LOCALDIR} ]];then
    debug "LOCALDIR set in config file to: ${LOCALDIR}"
else
    debug "Using NAME as localdir: ${NAME}"
    LOCALDIR=${NAME}
fi

# Aquire a lock to make sure we only run one instance of rsync at a time
exec 9>${LOCK}
if ! flock -n 9;then
    debug "Failed to aquire lock for: ${NAME}"
    exit -2
fi

#check if the log dir exists, otherwise create it
if [[ ! -d ${LOGDIR} ]];then
    debug "log dir does not exist, creating it"
    mkdir -p ${LOGDIR}
fi

#if RSYNC_PASSWORD is set we need to export it
if [[ ! -z ${RSYNC_PASSWORD} ]];then
    debug "exporting RSYNC_PASSWORD"
    export RSYNC_PASSWORD=${RSYNC_PASSWORD}
fi

if [ "X${TWOSTAGE}" = "XTrue" ]; then
    debug "Starting stage one in sync"
    debug "${STAGE1CMD} >> ${LOGCMD} 2>&1"
    ${STAGE1CMD} >> ${LOGCMD} 2>&1
    EXIT=$?
    if [[ ${EXIT} -eq 0 ]]; then
        debug "Starting stage two in sync"
        debug "${STAGE2CMD} >> ${LOGCMD} 2>&1"
        ${STAGE2CMD} >> ${LOGCMD} 2>&1
        EXIT=$?
    else
        echo "ERROR exit value from first sync is ${EXIT}. Second sync is not being started." >> ${LOGCMD} 2>&1
    fi
else
    # Normal single-stage sync
    debug "Syncing with following sync cmdline:"

    # if SSH_USER is nonempty, sync using ssh
    if [ ${SSH_USER} ]; then
        debug "${RSYNCCMD} ${RSYNC_OPTIONS} ${SSH_USER}@${REMOTE_HOST}:${REMOTE_DIR} /srv/mirrors/${LOCALDIR} >> ${LOGCMD} 2>&1"
        ${RSYNCCMD} ${RSYNC_OPTIONS} ${SSH_USER}@${REMOTE_HOST}:${REMOTE_DIR} /srv/mirrors/${LOCALDIR} >> ${LOGCMD} 2>&1
    else
        debug "${RSYNCCMD} ${RSYNC_OPTIONS} rsync://${REMOTE_HOST}${REMOTE_DIR} /srv/mirrors/${LOCALDIR} >> ${LOGCMD} 2>&1"
        ${RSYNCCMD} ${RSYNC_OPTIONS} rsync://${REMOTE_HOST}${REMOTE_DIR} /srv/mirrors/${LOCALDIR} >> ${LOGCMD} 2>&1
    fi

    EXIT=$?
fi

if [[ ${EXIT} -eq 0 ]];then
    DATE=`date +%s`
    debug "Sync completed succesfully"
    debug "Date: ${DATE}"
    echo ${DATE} > "${LASTSYNCFILE}"
else
    debug "Sync finished with errors"
    debug "Exit status: ${EXIT}"
fi
echo "Exit status: ${EXIT}" >> ${LOGCMD}

# unset again to not leave stuff hanging
if [[ ! -z ${RSYNC_PASSWORD} ]];then
    unset RSYNC_PASSWORD
fi
