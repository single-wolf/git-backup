# git-backup


## Overview

**git-backup.sh** is a shell script for `automatic and incremental backup` of git repositories. Using this script, developers don’t need to worry about losing code due to incorrect merge branches and other computer emergencies. Have fun with it `XD`

**Features**:

1. Incrementally back up code to backup branch without modify current working tree and index
2. Execute once or periodically execute the back up by setting a cron
3. Support push backup branch to remote repositories and track the remote one
4. Support directory mode so that can back up all repositories under the given directory

**TODO**:(Contributions welcome)

- Support backup branch management, such as prune history backup periodically
- Add a special git hook to the repository, so that only fetch the backup branch that belong to current user from remote
- Support authentication when push the backup to remote
- ...


## What It Does

- backup branch name `BACKUP${CURRENT_BRANCH}-${USR_NAME}` so that the backup will not conflict between developers
- detect the local and remote backup branch, compare the current working tree and index with latest backup if it exists
- skip the backup if current status is up-to-date or current working tree was already backup
- Add all file to backup branch and commit, push to remote if the option `-p` is given
- checkout current branch and recovery current working tree and index

## Usage

#### Synopsis

``` bash
git-backup.sh [-h] [-d] [repo-dir] [-c] [cron expression] [-p] [-n] [-r] [-l]
```

#### Description :

- [repo-dir]        the directory of git repository specified by `-d`, default is .
- [cron expression] cron expression of back up the git repo periodically,  specified by `-c`

#### Options :

- [-h] --help , print usage info and exit
- [-d] --dir [repo-dir] , specify the git repository
- [-p] --push , push the backup to remote, optional
- [-l] --log  , specify the periodical backup log file, default is ~/.gitbackup.log
- [-r] --recur, dir recurtive mode, backup all subdir at [repo-dir]
- [-n] --now  , do back up once right now
- [-c] --cron [cron expression], do back up periodically
- [-c/-n] must given at least one of two option

#### Examples :

1. Backup current git repository regularly and push remote
	- ./git-backup.sh -p -c '0 12 * * *'
2. Backup specified git repository once locally
	- ./git-backup.sh -n -d /User/xx/git-repo
3. Backup all subdirectory under /User/xx once and push remote
	- ./git-backup.sh -n -r -p -d /User/xx/

## License

[MIT License](./LICENSE).

