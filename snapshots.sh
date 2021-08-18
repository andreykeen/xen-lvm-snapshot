#!/bin/bash

#
#  Written in September 2018
#  Updated on February 08, 2019
#  Updated on April 17, 2019
#
#  by Andrey Vladimirskiy
#  andrey.vladimirskiy@gmail.com
#



# Синтаксис
# name:flag
# name - имя lvm-тома
# flag: vm - это виртуальная машина, нужно архивировать весь раздел, как файл
#       dt - это раздел с данными, нужно монтировать раздел в каталог и архивировать то, что находится в нём

VM_LIST=(
    "server1c:vm"
    "win:vm"
    "data:dt"
)



LV_PREFIX="guest-"
VG_NAME="vg-main"

STORAGE="/mnt/nas"
BACKUP_DATA="/mnt/data"

LOG_FILE="/opt/snapshots.log"

DEBUG="false"
REPORT_VIA_TELEGRAM="true"


################################################################################


log() {
    if [ "${1}" = " " ]; then
        echo >> "${LOG_FILE}"
    else
        echo ${1}
        echo "`date "+%Y.%m.%d %H:%M:%S"`  ${1}" >> "${LOG_FILE}"
    fi
}

log_tlg() {
    echo ${1}
    echo "`date "+%Y.%m.%d %H:%M:%S"`  ${1}" >> "${LOG_FILE}"

    if [ "${REPORT_VIA_TELEGRAM}" = "true" ]; then
        telegram-send "`date "+%Y.%m.%d %H:%M:%S"`  ${1}"
    fi
}

log_debug() {
    if [ "${DEBUG}" = "true" ]; then
        echo "DEBUG: ${1}"
        echo "`date "+%Y.%m.%d %H:%M:%S"`  DEBUG: ${1}" >> "${LOG_FILE}"
    fi
}

log_error() {
    echo "ERROR: ${1}"
    echo "`date "+%Y.%m.%d %H:%M:%S"`  ERROR: ${1}" >> "${LOG_FILE}"

    if [ "${REPORT_VIA_TELEGRAM}" = "true" ]; then
        telegram-send "`date "+%Y.%m.%d %H:%M:%S"`  ERROR: ${1}"
    fi

    if [ ${#} -ne 2 -o "${2}" != "noexit" ]; then
        echo "ERROR: Exit 1"
        echo "`date "+%Y.%m.%d %H:%M:%S"`  ERROR: Exit 1" >> "${LOG_FILE}"
        exit 1
    fi
}


set_variable() {
    if [ ${#} -ne 1 ]; then
        log_error "Function set_variable() should one argument"
    fi

    VM_NAME=`echo ${VM_LIST[${1}]} | awk -F: '{print $1}'`

    FLAG=`echo ${VM_LIST[${1}]} | awk -F: '{print $2}'`
    # TODO: Проверка на флаги

    UUID=`echo ${VM_LIST[${1}]} | awk -F: '{print $3}'`
    if [ "${UUID}" = "" ]; then
        UUID=`uuidgen`
        VM_LIST[$i]="${VM_LIST[$i]}:${UUID}"
    fi

    LV_NAME="${LV_PREFIX}${VM_NAME}"
    LV_PATH="/dev/${VG_NAME}/${LV_NAME}"
    LV_SIZE=`lvs --noheadings --options lv_size --units g --nosuffix "${LV_PATH}" 2> /dev/null`

    SNAP_NAME="${LV_NAME}-snap-${UUID}"
    SNAP_PATH="/dev/${VG_NAME}/${SNAP_NAME}"
    SNAP_SIZE=`echo "x=(${LV_SIZE} * 10 / 100); if (x==0) x=1; print x, \"\n\"" | bc`

    if [ ${SNAP_SIZE} -eq 0 ]; then
        log_error "For '${LV_PATH}' snap size can not be zero"
    fi
}


vm_worker() {
    log "Start calculation checksum of '${SNAP_PATH}'"
    md5sum "${SNAP_PATH}" > "${STORAGE}/${LV_NAME}_${SNAP_DATE}.md5"
    RET=`echo $?`
    if [ ${RET} -ne 0 ]; then
        log_error "[${RET}] Can not calculate checksum of '${SNAP_PATH}'"
    fi

    CHECKSUM_1=`cat "${STORAGE}/${LV_NAME}_${SNAP_DATE}.md5" | awk '{print $1}'`
    log "Checksum calculation completed '${STORAGE}/${LV_NAME}_${SNAP_DATE}.md5'"


    log "Start archivation of '${SNAP_PATH}'"
    gzip -k -c -9 "${SNAP_PATH}" > "${STORAGE}/${LV_NAME}_${SNAP_DATE}.gz"
    RET=`echo $?`
    if [ ${RET} -ne 0 ]; then
        log_error "[${RET}] Can not create archive of '${SNAP_PATH}'"
    fi

    log "Archivation completed '${STORAGE}/${LV_NAME}_${SNAP_DATE}.gz'"


    log "Start unpacking archive and verification checksum '${STORAGE}/${LV_NAME}_${SNAP_DATE}.gz'"
    CHECKSUM_2=`gzip -k -c -d "${STORAGE}/${LV_NAME}_${SNAP_DATE}.gz" | md5sum | awk '{print $1}'`
    echo "${CHECKSUM_2}  ${STORAGE}/${LV_NAME}_${SNAP_DATE}.gz (unpacked)" >> "${STORAGE}/${LV_NAME}_${SNAP_DATE}.md5"

    if [ "${CHECKSUM_1}" != "${CHECKSUM_2}" ]; then
        log_error "Verification checksum failed"
    fi
    log "Verification completed '${STORAGE}/${LV_NAME}_${SNAP_DATE}'"


    log "Copy configuration file '${VM_NAME}.conf'"
    cp "/opt/xen/${VM_NAME}.conf" "${STORAGE}/${LV_NAME}_${SNAP_DATE}.conf"
    RET=`echo $?`
    if [ ${RET} -ne 0 ]; then
        log_error "[${RET}] Can not copy config file '${VM_NAME}.conf'"
    fi
}


dt_worker() {
    mount "${SNAP_PATH}" "${BACKUP_DATA}"
    RET=`echo $?`
    if [ ${RET} -ne 0 ]; then
        log_error "[${RET}] Can not mount '${SNAP_PATH}' to '${BACKUP_DATA}'"
    fi

    mkdir -p "${STORAGE}/data"
    RET=`echo $?`
    if [ ${RET} -ne 0 ]; then
        log_error "[${RET}] Can not create directory '${STORAGE}/data'"
    fi

    DIR_LIST=`ls "${BACKUP_DATA}"`
    for loop in ${DIR_LIST}
    do
        if [ -d "${BACKUP_DATA}/${loop}" ]; then
            if [ "${loop}" != "lost+found" ]; then
                log "Archivation directory '${BACKUP_DATA}/${loop}' to '${STORAGE}/data/${loop}_${SNAP_DATE}.tgz'"
                tar -czf "${STORAGE}/data/${loop}_${SNAP_DATE}.tgz" -C "${BACKUP_DATA}/${loop}" .
                RET=`echo $?`
                if [ ${RET} -ne 0 ]; then
                    log_error "[${RET}] Can not to create an archive '${STORAGE}/data/${loop}_${SNAP_DATE}.tgz'"
                fi
            fi
        fi
    done

    umount "${BACKUP_DATA}"
    RET=`echo $?`
    if [ ${RET} -ne 0 ]; then
        log_error "[${RET}] Can not unmount '${SNAP_PATH}' from '${BACKUP_DATA}'"
    fi
}


run_all_vm() {
    for i in ${!VM_LIST[*]}
    do
        set_variable ${i}
        log "Try run Virtual machine '${VM_NAME}'"
        if [[ "${FLAG}" = "vm"  ]]; then
            log "Creating Virtual machine '${VM_NAME}'"
            xl create "/opt/xen/${VM_NAME}.conf"
        fi
    done
}


remove_old_backups() {
    log "Remove old backups"

    ARCHIVE_DIR="/mnt/nas/archive"
    ARCHIVE_LIST_ALL=$(ls -l ${ARCHIVE_DIR} | awk '{print $9}')
    ARCHIVE_LIST_LAST_10=$(ls -l ${ARCHIVE_DIR} | awk '{print $9}' | sort | tail -10)

    for loop in ${ARCHIVE_LIST_ALL}
    do
        echo ">${loop}"
    done

}



################################################################################

log " "
log_tlg "Session started"


### Mount NAS and check free space
if [ -z "`mount | grep \"${STORAGE}\"`" ]; then
    mount -t cifs -o username=snapshot,password=snapshot //192.168.1.5/snapshot "${STORAGE}"
    RET=`echo $?`
    if [ ${RET} -ne 0 ]; then
        run_all_vm
        log_error "[${RET}] Can not mount '${STORAGE}'"
    fi
fi


#remove_old_backups


NAS_FREE=`df -BG --output='target,avail' | grep "${STORAGE}" | awk '{print $2}' | sed 's/G//g'`
if [ ${NAS_FREE} -lt 200 ]; then
    run_all_vm
    log_error "Not enough space on NAS"
fi
###




### Get free space in volume group 'vg-main'
VG_FREE=`vgs --noheadings --options vg_free --units g --nosuffix "${VG_NAME}" 2> /dev/null`
VG_FREE="${VG_FREE%%.*}"
VG_FREE="${VG_FREE##*[[:space:]]}"
###


### Check if logical volume exists and check free space in 'vg-main' for all snapshots
SNAP_SIZE_SUM=1
CURRENT_LV=`lvs --noheadings --options lv_path 2> /dev/null`

for i in ${!VM_LIST[*]}
do
    set_variable ${i}

    LV_EXIST="false"
    for loop in ${CURRENT_LV}
    do
        if [ "${loop}" = ${LV_PATH} ]; then
            LV_EXIST="true"
            break
        fi
    done
    if [ "${LV_EXIST}" = "false" ]; then
        log_error "LV '${LV_PATH}' not exist"
    fi

    SNAP_SIZE_SUM=$(( ${SNAP_SIZE_SUM} + ${SNAP_SIZE} ))
    if [ ${VG_FREE} -lt ${SNAP_SIZE_SUM} ]; then
        log_error "For snapshots you need ${SNAP_SIZE_SUM}G but in '${VG_NAME}' available ${VG_FREE}G"
    fi
done
###


SNAP_DATE=$(date "+%Y.%m.%d_%H.%M.%S")
STORAGE="${STORAGE}/archive/${SNAP_DATE}"

mkdir -p "${STORAGE}"
RET=`echo $?`
if [ ${RET} -ne 0 ]; then
    log_error "[${RET}] Can not create directory '${STORAGE}'"
fi


### Check if virtual machines is running
MAX_TRY=100
for i in ${!VM_LIST[*]}
do
    set_variable ${i}

    if [ "${FLAG}" = "vm"  ]; then

        COUNT=1
        WAIT_FLAG="false"
        while [ ${COUNT} -le ${MAX_TRY} ]
        do

            RUNNING_VM=`xl list`
            RES=`echo "${RUNNING_VM}" | grep "${VM_NAME}"`
            if [ -n "${RES}" ]; then

                if [ "${WAIT_FLAG}" = "false" ]; then

                    # Исключение для виртуальной машины 'win'. Она должна выключаться самостоятельно
                    if [ "${VM_NAME}" != "win" ]; then
                        xl shutdown "${VM_NAME}" 2> /dev/null
                        log "Send signal for shutdown '${VM_NAME}'"
                    fi

                    WAIT_FLAG="true"
                fi

            else
                break  # cycle 'while'
            fi

            log "Waiting stopping of the virtual machine '${VM_NAME}' [${COUNT}]"
            sleep 5

            (( COUNT++ ))
        done

        if [ ${COUNT} -gt ${MAX_TRY} ]; then
            log_error "Can not create snapshot because machine '${VM_NAME}' is running"
        else
            log "Virtual machine '${VM_NAME}' is shutdown"
        fi
    fi
done
###


for i in ${!VM_LIST[*]}
do
    set_variable ${i}

    log "Create snapshot of '${LV_PATH}'"
    lvcreate -s -L ${SNAP_SIZE}G -n ${SNAP_NAME} ${LV_PATH} 2> /dev/null > /dev/null
    RET=`echo $?`
    if [ ${RET} -ne 0 ]; then
        log_error "[${RET}] Can not create snapshot of ${LV_PATH}" "noexit"
    else
        log "Create snapshot completed '${SNAP_PATH}'"
    fi
done


# После создания снапшотов запускаются все ВМ и только после этого стартует создание бакапов
run_all_vm


for i in ${!VM_LIST[*]}
do
    set_variable ${i}

    if [ "${FLAG}" = "vm"  ]; then
        vm_worker
        echo -n
    elif [ "${FLAG}" = "dt"  ]; then
        dt_worker
        echo -n
    fi

    log "Remove snapshot '${SNAP_PATH}'"
    lvremove -f "${SNAP_PATH}" 2> /dev/null > /dev/null
    RET=`echo $?`
    if [ ${RET} -ne 0 ]; then
        log_error "[${RET}] Can not remove snapshot '${SNAP_PATH}'"
    fi
    log "Remove snapshot completed '${SNAP_PATH}'"

done

log_tlg "Session complete"
