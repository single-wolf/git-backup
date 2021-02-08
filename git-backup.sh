#!/usr/bin/env bash

#=============================================================================
# git-backup.sh --- A shell script for automatic and incremental backup of git repositories.
# Author: Jerry.Zhong < root.zhongm.in >
# Repository: https://github.com/single-wolf/git-backup
# Usage git-backup.sh [-h] [-d|--dir] [repo-dir] [-c|--cron] [cron expression] [-p|--push] [-n|--now]
# License: MIT
# Have fun XD
#=============================================================================

#printenv
#set -x

# script parameters from stdin
P_REPO_DIR="."
P_CRON_EXP=""
P_NEED_PUSH=false
P_IS_NOW=false
P_DIR_RECURSIVE=false
# env info
ENV_OSTYPE=""
CURRENT_TIME=""
LOG_PATH="~/.gitbackup.log"
# git info
BACKUP_PREFIX="BACKUP-"
ROOT_DIR=""
REPOSITORY_NAME=""
CURRENT_BRANCH=""
CURRENT_UP_STREAM=""
BACKUP_BRANCH=""
REMOTE_BACKUP_BRANCH=""
HAS_HISTORY=true
IS_LOCAL_CLEAN=false
USR_NAME=""

#constant
EXIT_CODE_SUCC=0

# print message
Green='\033[0;32m'  # Green
Red='\033[0;31m'    # Red
Yellow='\033[0;33m' # Yellow
Blue='\033[0;34m'   # Blue
Color_off='\033[0m' # Text Reset
function log_print() {
    printf '%b\n' "$1" >&2
}
function log_succ() {
    log_print "${Green}[✔]${Color_off} $@"
}
function log_info() {
    log_print "${Blue}[➭]${Color_off} $@"
}
function log_error() {
    log_print "${Red}[✘]${Color_off} $@"
}
function log_warn() {
    log_print "${Yellow}[⚠]${Color_off} $@"
}

# set cron to os
function set_cron() {
    local script_name=$(basename "$0")
    local script_dir="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)"
    local script_param=" -n -d ${P_REPO_DIR} "
    if ${P_NEED_PUSH}; then
        script_param="${script_param} -p"
    fi
    if ${P_DIR_RECURSIVE}; then
        script_param="${script_param} -r"
    fi
    if [[ ${ENV_OSTYPE} == "OSX" || ${ENV_OSTYPE} == "Linux" ]]; then
        local cron_setting="${P_CRON_EXP} ${script_dir}/${script_name} ${script_param} >> ${LOG_PATH} 2>&1"
        (
            crontab -l 2>/dev/null | grep -Fv "${script_name}.*?${REPOSITORY_NAME}"
            echo "${cron_setting}"
        ) | crontab -
    else
        if ! which "schtasks" >>/dev/null; then
            log_error "Sorry, Cannot find schtasks command on ${ENV_OSTYPE} OS  Q_Q"
            return 1
        fi
        cron_setting="${script_dir}/${script_name} ${script_param} >> ${LOG_PATH} 2>&1"
        local bash_path=$(where "bash")
        if [[ $? -ne ${EXIT_CODE_SUCC} ]]; then
            log_error "Sorry, Cannot find bash location on ${ENV_OSTYPE} OS  Q_Q"
            return 1
        fi
        local win_command="\"${bash_path} ${cron_setting}\""
        local win_cron_setting="/Create /sc minute /mo 1 /tn \"Git-Repo Backup\" /tr ${win_command} "
        win_cron_setting=${win_cron_setting//\//\/\/}
        schtasks "${win_cron_setting}"
    fi
    if [[ $? -ne ${EXIT_CODE_SUCC} ]]; then
        log_error "Setting cron config failed, OS : ${ENV_OSTYPE},  config : ${cron_setting}"
    else
        log_succ "Setting cron successfully, OS : ${ENV_OSTYPE},  config : ${cron_setting}"
    fi
}

# init env param
function init_env_param() {
    local unamestr=$(uname -s | tr '[:upper:]' '[:lower:]')
    case ${unamestr} in
    linux*)
        ENV_OSTYPE="Linux"
        ;;
    msys* | mingw*)
        ENV_OSTYPE="Windows"
        ;;
    darwin*)
        ENV_OSTYPE="OSX"
        ;;
    *)
        log_warn "Cannot detect OS type, Script may not works well"
        ENV_OSTYPE="UNKNOW"
        ;;
    esac
    # relative path to absolute path
    if [[ ! ${P_REPO_DIR} =~ ^"/" ]]; then
        P_REPO_DIR="${PWD}/${P_REPO_DIR}"
    fi
    if ! cd ${P_REPO_DIR} >>/dev/null; then
        log_error "Cannot cd the git repo directory : ${P_REPO_DIR}"
        return 1
    fi
    if ! ${P_DIR_RECURSIVE}; then
        ROOT_DIR=$(git rev-parse --show-toplevel)
        if [[ $? -ne ${EXIT_CODE_SUCC} ]]; then
            log_error "The directory is not a git repo : ${P_REPO_DIR}"
            return 1
        fi
        if ! cd ${ROOT_DIR} >>/dev/null; then
            log_error "Cannot cd the root dir of git repo directory : ${ROOT_DIR}"
            return 1
        fi
        REPOSITORY_NAME=$(basename "${ROOT_DIR}")
    fi
}

# init git param, should after init_env_param
function init_git_param() {
    echo ""
    log_info "=============================================================================="
    log_succ "==    Repository ${REPOSITORY_NAME}"
    log_succ "==    Ready to back up Git at ${ROOT_DIR}"
    log_info "=============================================================================="
    echo ""
    cd ${ROOT_DIR}
    local headstr=$(git symbolic-ref HEAD)
    if [[ $? -eq ${EXIT_CODE_SUCC} ]]; then
        CURRENT_BRANCH=$(basename "${headstr}")
    else
        # in case of detach HEAD
        CURRENT_BRANCH=$(git rev-parse --short HEAD)
        if [[ $? -ne ${EXIT_CODE_SUCC} ]]; then
            log_error "Unknown ref of HEAD, exit"
            return 1
        fi
    fi
    CURRENT_UP_STREAM=$(git rev-parse --abbrev-ref ${CURRENT_BRANCH}@{upstream})
    CURRENT_TIME=$(date +"%Y%m%d%H%m%S")
    USR_NAME=$(git config user.name)
    if [[ -z ${USR_NAME} ]]; then
        USR_NAME=$(id -u -n)
    fi
    BACKUP_BRANCH="${BACKUP_PREFIX}${CURRENT_BRANCH}-${USR_NAME}"
    if ! git rev-parse --quiet --verify ${BACKUP_BRANCH} >/dev/null; then
        log_info "Cannot find a local backup branch , will try remote, name : ${BACKUP_BRANCH}"
        for remote in $(git remote); do
            remote_branch="remotes/${remote}/${BACKUP_BRANCH}"
            if git rev-parse --quiet --verify ${remote_branch} >/dev/null; then
                REMOTE_BACKUP_BRANCH="${remote_branch}"
                break
            fi
        done
        if [[ -z ${REMOTE_BACKUP_BRANCH} ]]; then
            log_info "Cannot find a remote backup branch , will create one"
            HAS_HISTORY=false
        else
            log_info "Find a remote backup branch , create local branch to track it, name : ${REMOTE_BACKUP_BRANCH}"
            if ! git branch -q ${BACKUP_BRANCH} --track ${REMOTE_BACKUP_BRANCH}; then
                log_error "Failed to create local branch to track it, name : ${REMOTE_BACKUP_BRANCH}"
                return 1
            fi
        fi
    fi
}

# check current status
function pre_check() {
    echo ""
    log_info "=============================================================================="
    log_info "==    Pre-check branch ${CURRENT_BRANCH} at ${ROOT_DIR}"
    log_info "=============================================================================="
    echo ""
    cd ${ROOT_DIR}
    # prevent conflict
    if [[ -e ".git/index.lock" ]]; then
        log_warn "Abort because there have a index.lock, ${P_REPO_DIR}.git/index.lock"
        return 1
    fi
    is_up_to_date=false
    is_equal_his=false
    if [[ -z $(git status -s -uall) ]]; then
        IS_LOCAL_CLEAN=true
        # exist upstream
        if [[ -n ${CURRENT_UP_STREAM} ]]; then
            if git diff --quiet ${CURRENT_BRANCH} ${CURRENT_UP_STREAM}; then
                is_up_to_date=true
            fi
        fi
    fi
    # exist history backup branch
    if ${HAS_HISTORY}; then
        local history_hash=$(git rev-parse ${BACKUP_BRANCH}^{tree})
        local tmp_index_file=$(mktemp)
        cp $(git rev-parse --git-dir)/index ${tmp_index_file}
        local now_hash=$(git add -A && git write-tree)
        if [[ ${history_hash} == ${now_hash} ]]; then
            is_equal_his=true
        fi
        cp ${tmp_index_file} $(git rev-parse --git-dir)/index && rm -f ${tmp_index_file}
    fi
    if ${is_equal_his}; then
        log_succ "Local working tree was already backed up, skip and exit"
        return 1
    else
        if ${is_up_to_date}; then
            log_succ "Local working tree is clean and up-to-date, skip and exit"
            return 1
        else
            if ${IS_LOCAL_CLEAN}; then
                log_info "Local working tree is clean but no upstream or not up-to-date, will back up"
            else
                log_info "Local working tree is dirty and no backup or modified after back up, will back up"
            fi
        fi
    fi
}

# back up git repository
function backup_now() {
    backup_start
    # stash current working tree if dirty
    if ! ${IS_LOCAL_CLEAN}; then
        git stash push -u -m "Backup at ${CURRENT_TIME}" && git stash apply --index -q
    fi
    if [[ $? -eq ${EXIT_CODE_SUCC} ]]; then
        # directly checkout if no backup history
        if ! ${HAS_HISTORY}; then
            git checkout -b "${BACKUP_BRANCH}"
        else
            git reset -q --mixed HEAD && git symbolic-ref HEAD "refs/heads/${BACKUP_BRANCH}"
        fi
        # sometimes no need to commit
        if [[ -n $(git status -s -uall) ]]; then
            git add -A && git commit -q -am "Backup at ${CURRENT_TIME}" --no-verify
        fi
        if [[ $? -eq ${EXIT_CODE_SUCC} ]]; then
            log_succ "Back up branch ${CURRENT_BRANCH} to local ${BACKUP_BRANCH} successfully"
            git checkout -q -f "${CURRENT_BRANCH}" && if ! ${IS_LOCAL_CLEAN}; then git stash pop --index -q; fi
            if ${P_NEED_PUSH}; then
                push_remote
            fi
            backup_done
        else
            log_error "Back up branch ${CURRENT_BRANCH} fail, try to recover it"
            # we should clean backup branch
            git reset -q --hard HEAD && git clean -q -f -d
            git checkout -q -f "${CURRENT_BRANCH}" && git reset -q --hard HEAD && if ! ${IS_LOCAL_CLEAN}; then git stash pop --index -q; fi
            return 1
        fi
    else
        log_error "Failed to stash current working tree temporarily"
        return 1
    fi
}

# push backup to remote
function push_remote() {
    if [[ -n ${CURRENT_UP_STREAM} ]]; then
        remote_backup="${CURRENT_UP_STREAM%%/*}"
        git push -q --no-verify --set-upstream "${remote_backup}" "${BACKUP_BRANCH}:${BACKUP_BRANCH}"
        log_succ "Push backup branch to remote successfully, name : ${remote_backup}/${BACKUP_BRANCH}"
    else
        log_warn "No upstream found at current branch:${CURRENT_BRANCH}, will try all remote to push backup"
        if [[ -z $(git remote) ]]; then
            log_error "No remote found in this git-repo:${ROOT_DIR}, Push failed"
            return 1
        fi
        for remote in $(git remote); do
            if git push -q --no-verify --set-upstream "${remote}" "${BACKUP_BRANCH}:${BACKUP_BRANCH}"; then
                log_succ "Push backup branch to remote successfully, name : ${remote}/${BACKUP_BRANCH}"
                return 0
            else
                log_warn "Push backup branch to remote failed, name : ${remote}/${BACKUP_BRANCH}"
            fi
        done
    fi
    return 1
}

# print backup start
function backup_start() {
    echo ""
    log_info "=============================================================================="
    log_info "==    Start Back up branch ${CURRENT_BRANCH} at ${ROOT_DIR}"
    log_info "=============================================================================="
    echo ""
}

# print backup done
function backup_done() {
    echo ""
    log_info "Back up done!"
    log_info "=============================================================================="
    log_succ "==    Back up branch ${CURRENT_BRANCH} to ${BACKUP_BRANCH}"
    log_info "=============================================================================="
    echo ""
}

# directory recurtive backup
function recurtive_backup() {
    if [[ -z $(ls -d */) ]]; then
        log_error "Recutive git repo directory is empty and no subdirectory : ${P_REPO_DIR}"
        return 1
    fi
    if [[ -n ${P_CRON_EXP} ]]; then
        set_cron
    fi
    if ${P_DIR_RECURSIVE}; then
        local param_recur="--log ${LOG_PATH}"
        if ${P_IS_NOW}; then
            param_recur="${param_recur} -n"
        fi
        if ${P_NEED_PUSH}; then
            param_recur="${param_recur} -p"
        fi
        local script_name=$(basename "$0")
        local script_dir="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)"
        for sub_dir in $(ls -d */); do
            cd ${P_REPO_DIR}
            param_recur="${param_recur} -d ${P_REPO_DIR}/${sub_dir}"
            bash -c "${script_dir}/${script_name} ${param_recur}"
        done
    fi
}

## print usage help info and exit
function print_help() {
    if [[ "${LANG}" == "zh_CN"* ]]; then
        log_info "命令简介  git-backup.sh [-h] [-d|--dir] [repo-dir] [-c|--cron] [cron expression] [-p|--push] [-n|--now]"
        log_info "描述 : "
        log_info "[repo-dir]        可选，Git仓库目录，不传默认当前目录"
        log_info "[cron expression] 备份Git仓库的cron表达式"
        log_info "选项 : "
        log_info "[-h] --help , 打印使用说明"
        log_info "[-d] --dir [repo-dir]"
        log_info "[-p] --push , 将备份推送远程仓库, 可选"
        log_info "[-l] --log  , 日志文件, 可选, 默认~/.gitbackup.log"
        log_info "[-r] --recur, 目录模式, 备份[repo-dir]下所有子目录"
        log_info "[-n] --now  , 立即执行一次备份"
        log_info "[-c] --cron [cron expression], 定时执行备份"
        log_info "[-c/-n] 命令选项二选一必填"
        log_info "示例 :  "
        log_info "1. 按cron表达式定时备份当前目录Git仓库，并推送远程仓库"
        log_info "       ./git-backup.sh -p -c '0 12 * * *' "
        log_info "2. 仅执行一次指定目录Git仓库备份，不推送远程仓库"
        log_info "      ./git-backup.sh -n -d /User/xx/git-repo "
        log_info "3. 执行一次指定目录下所有子目录备份，并推送远程仓库"
        log_info "      ./git-backup.sh -n -r -p -d /User/xx/"
    else
        log_info "SYNOPSIS git-backup.sh [-h] [-d|--dir] [repo-dir] [-c|--cron] [cron expression] [-p|--push] [-n|--now]"
        log_info "DESCRIPTION : "
        log_info "[repo-dir]        the directory of git repository specified by -d , default is ."
        log_info "[cron expression] cron expression of back up the git repo periodically, specified by -c"
        log_info "OPTIONS : "
        log_info "[-h] --help , print usage info"
        log_info "[-d] --dir [repo-dir], specify the git repository"
        log_info "[-p] --push , push the backup to remote, optional"
        log_info "[-l] --log  , specify the periodical backup log file, default is ~/.gitbackup.log"
        log_info "[-r] --recur, dir recursive mode, backup all subdir at [repo-dir]"
        log_info "[-n] --now  , do back up once right now"
        log_info "[-c] --cron [cron expression], do back up periodically"
        log_info "[-c/-n] must given at least one of two option"
        log_info "EXAMPLE :  "
        log_info "1. Backup current git repository regularly and push remote"
        log_info "       ./git-backup.sh -p -c '0 12 * * *' "
        log_info "2. Backup specified git repository once locally"
        log_info "      ./git-backup.sh -n -d /User/xx/git-repo "
        log_info "3. Backup all subdirectory under /User/xx once and push remote"
        log_info "      ./git-backup.sh -n -r -p -d /User/xx/"
    fi
    exit 1
}

## parse the parameters
function parse_param() {
    local idx=0
    local all_param=("$@")
    local param_num=$#
    until [[ ${idx} -ge $# ]]; do
        param=${all_param[${idx}]}
        if [[ ${param} =~ ^"-" ]]; then
            if [[ ${param} == "-h" || ${param} == "-help" || ${param} == "--help" ]]; then
                print_help
            elif [[ ${param} == "-d" || ${param} == "--dir" ]]; then
                ((idx++))
                if [[ ${idx} -ge ${param_num} || ${all_param[${idx}]} =~ ^"-" ]]; then
                    log_error "Option Should has parameter [-d|--dir] /xxx/git-repo or ../git-repo"
                    print_help
                fi
                P_REPO_DIR=${all_param[${idx}]}
            elif [[ ${param} == "-c" || ${param} == "--cron" ]]; then
                ((idx++))
                if [[ ${idx} -ge ${param_num} || ${all_param[${idx}]} =~ ^"-" ]]; then
                    log_error "Option Should has parameter [-c|--cron] \"0 * * * *\""
                    print_help
                fi
                P_CRON_EXP=${all_param[${idx}]}
            elif [[ ${param} == "-n" || ${param} == "--now" ]]; then
                P_IS_NOW=true
            elif [[ ${param} == "-p" || ${param} == "--push" ]]; then
                P_NEED_PUSH=true
            elif [[ ${param} == "-r" || ${param} == "--recursive" ]]; then
                P_DIR_RECURSIVE=true
            elif [[ ${param} == "-l" || ${param} == "--log" ]]; then
                ((idx++))
                if [[ ${idx} -ge ${param_num} || ${all_param[${idx}]} =~ ^"-" ]]; then
                    log_error "Option Should has parameter [-l|--log] ~/.git-backup.log"
                    print_help
                fi
                LOG_PATH=${all_param[${idx}]}
            else
                print_help
            fi
        else
            print_help
        fi
        idx=$(expr $idx + 1)
    done
    if [[ -z ${P_CRON_EXP} && ! ${P_IS_NOW} ]]; then
        log_warn "[-c/-n] must have one of two option at lease"
        print_help
    fi
}

function main() {
    if [ $# -gt 0 ]; then
        parse_param "$@"
        init_env_param || exit 1
        # dir recursive mode
        if ${P_DIR_RECURSIVE}; then
            recurtive_backup
        else
            if [[ -n ${P_CRON_EXP} ]]; then
                set_cron || exit 1
            fi
            # backup flow
            if ${P_IS_NOW}; then
                init_git_param && pre_check && backup_now
            fi
        fi
    else
        print_help
    fi
}

main "$@"

#set +x
