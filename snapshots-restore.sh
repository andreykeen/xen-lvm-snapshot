#!/bin/bash

# Не доделано


#########################################

# VM_LIST=("server1c:vm" "win:vm" "servervpn:vm")
VM_LIST=("win:vm")

SNAP_DATE="2020.09.06_00.10.14"


LV_PREFIX="guest-"
VG_NAME="vg-main"
#STORAGE="/mnt/nas/archive"
STORAGE="/mnt/backup"

XEN_DIR="/opt/xen"
LOG_FILE="/opt/snapshots-restore.log"
DEBUG="true"


#########################################



log() {
    echo -e ${1}
    echo -e "`date "+%Y.%m.%d %H:%M:%S"`  ${1}" >> "${LOG_FILE}"
}

log_debug() {
    if [ "${DEBUG}" = "true" ]; then
        echo -e "DEBUG: ${1}"
        echo -e "`date "+%Y.%m.%d %H:%M:%S"`  DEBUG: ${1}" >> "${LOG_FILE}"
    fi
}

log_error() {
    echo -e "ERROR: ${1}"
    echo -e "`date "+%Y.%m.%d %H:%M:%S"`  ERROR: ${1}" >> "${LOG_FILE}"
    exit 1
}

is_exist() {
    test ! -r "${1}" && log_error "Not found '${1}'"
    log_debug "File exist: ${1}"
}

set_variable() {
    if [ ${#} -ne 1 ]; then
        log_error "Function set_variable() should one argument"
    fi

    VM_NAME=`echo ${VM_LIST[${1}]} | awk -F: '{print $1}'`
    DST_LV_PATH="/dev/${VG_NAME}/${LV_PREFIX}${VM_NAME}"
}





################################################################################

log "Session started"


### Mount NAS and check free space
# if [ -z "`mount | grep \"${STORAGE}\"`" ]; then
#     mount -t cifs -o username=snapshot,password=snapshot //192.168.1.5/snapshot "${STORAGE}"
#     RET=`echo $?`
#     if [ ${RET} -ne 0 ]; then
#         log_error "[${RET}] Can not mount '${STORAGE}'"
#     fi
# fi
###


for i in ${!VM_LIST[*]}
do
    set_variable ${i}

    log_debug "VM_NAME: ${VM_NAME}"

    is_exist "${STORAGE}/${SNAP_DATE}/${LV_PREFIX}${VM_NAME}_${SNAP_DATE}.conf"
    is_exist "${STORAGE}/${SNAP_DATE}/${LV_PREFIX}${VM_NAME}_${SNAP_DATE}.gz"
    is_exist "${STORAGE}/${SNAP_DATE}/${LV_PREFIX}${VM_NAME}_${SNAP_DATE}.md5"

    is_exist "${DST_LV_PATH}"
done



for i in ${!VM_LIST[*]}
do
    set_variable ${i}

    log "Start writing from '${STORAGE}/${SNAP_DATE}/${LV_PREFIX}${VM_NAME}_${SNAP_DATE}.gz' to '${DST_LV_PATH}'"
    gzip -d -k -c "${STORAGE}/${SNAP_DATE}/${LV_PREFIX}${VM_NAME}_${SNAP_DATE}.gz" > "${DST_LV_PATH}"
    log "Writing completed '${DST_LV_PATH}'"

    log "Start verification checksum '${DST_LV_PATH}'"
    CHECKSUM_1=`md5sum "${DST_LV_PATH}" | awk '{print $1}'`
    log "Checksum calculation completed '${DST_LV_PATH}' ${CHECKSUM_1}"

    CHECKSUM_2=$(cat "${STORAGE}/${SNAP_DATE}/${LV_PREFIX}${VM_NAME}_${SNAP_DATE}.md5" | sed -n '1p' | awk '{print $1}')
    log "Checksum from '${STORAGE}/${SNAP_DATE}/${LV_PREFIX}${VM_NAME}_${SNAP_DATE}.md5' ${CHECKSUM_2}"

    if [ "${CHECKSUM_1}" != "${CHECKSUM_2}" ]; then
        log_error "Verification checksum failed"
    fi
    log "Verification checksum completed"

    cp "${STORAGE}/${SNAP_DATE}/${LV_PREFIX}${VM_NAME}_${SNAP_DATE}.conf" "${XEN_DIR}/${VM_NAME}.conf"
    RET=`echo $?`
    if [ ${RET} -ne 0 ]; then
        log_error "[${RET}] Can not copy '${STORAGE}/${SNAP_DATE}/${LV_PREFIX}${VM_NAME}_${SNAP_DATE}.conf' to '${XEN_DIR}'"
    fi

done


log "Session completed\n"

