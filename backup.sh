#!/bin/sh
########################################################################################
# In order to work without requiring a password to logon to remote system, copy local
# .ssh/id_rsa.pub to .ssh/authorized_keys on remote system. In case .ssh/authorized_keys
# already exists, append using cat id_rsa.pub >> authorized_keys. If .ssh/id_rsa.pub
# does not exist yet, generate using ssh-keygen -t rsa. Permission on .ssh dir must be
# 755, permission on authorized_keys file 644.
#
# Alternatively, use rsh shell. Put a line in remote ~/.rhosts containing the full name
# of the local machine (host.domain.tld) to avoid password prompt. The .rhosts file
# must be readable by user only (chmod 600)
#
# Add to crontab by including following line using crontab -e (assuming job will run
# at 2AM):
# 0 2 * * * /root/scripts/<name of this script> 2>&1 >/dev/null
########################################################################################


# Find home dir of current user, even if reset by cron environment
HOME=$(eval echo ~$(id -un))

# Title for email messages
TITLE="System Backup"

# Email address for daily updates
DYLY_EMAIL="root@example.com"

# Email address for weekly updates and errors
WKLY_EMAIL="user@example.com"

# Should we do weekly backups (every Monday)?
WEEKLY=true

# Should we do monthly backup (every first Monday of the month)?
MONTHLY=true

# SSH Port
SSH_PORT=22

# Source user@host (empty for local)
SRC_HOST=""

# Source path (use $HOME for the home directory)
SRC_PATH='/'

# Mount path for backup (empty for none)
MNT_PATH=''

# Destination user@host (empty for local)
DST_HOST="user@remote.example.com"

# Destination path (use $HOME for the home directory)
DST_PATH='/mnt/backup'

# Files and directories to be included
INCL="/dev/console /dev/initctl /dev/null /dev/zero"

# Files and directories to be excluded
EXCL="/dev/* /proc/* /sys/* /tmp/* lost+found/ /home/*"

# Directory for lock file
LOCKDIR="/var/run"

# Number of times to retry rsync in case of error
MAXTRIES=10

# Wait time between rsync attempts in seconds
SLEEPTIME=1800


# Is process running and from this executable?
# arg1: pid of process to check
function checkproc {
  local myname
  local procname

  myname=$(basename -- "$0")
  # name of process belonging to pid
  procname=$( ps -o comm= -p "$1")
  [ "$myname" = "$procname" ]
  return $?
}


# Execute command either remotely or locally, depending
# on whether an destination host is defined. Retry on ssh 255 error.
# arg1: bash command(s) to be executed
function myexec {
  local EC=-1
  local TRIES=0
  while [ "$TRIES" -eq 0 -o \
          "$DST_HOST" -a "$EC" -eq 255 -a "$TRIES" -lt "$MAXTRIES" ]; do
    [ "$TRIES" -ne 0 ] && { sleep "$SLEEPTIME"; echo "--"; }
    if [ "$DST_HOST" ]; then
      /usr/bin/ssh -p"${SSH_PORT}" -i"$HOME/.ssh/id_rsa" "${DST_HOST}" "sh -c '$1'" 2>&1
      EC=$?
    else
      eval "eval '$1'" 2>&1
      EC=$?
    fi
  let TRIES+=1
  done
  return $EC
}

#myexec 'LNK=$(date);echo $LNK'
#myexec 'LNK=$(ls -tl . | sed -n "s@\(\S\+\).*@\1@p");echo "$LNK"'
#a=$(myexec 'LNK=$(ls -tl . | sed -n "s@\(\S\+\).*@\1@p");echo "$LNK"')
#echo "$a"


# Remote command to find current directory
# All newlines escaped for remote csh exectution
curcmd=\
'ERR=false; \
if [ -d "'"$DST_PATH"'" ]; then \
   CUR=$(readlink "'"${DST_PATH}/current"'") || \
     CUR=$(ls -tl "'"$DST_PATH"'" | \
     sed -n "s@^d\(\S\+\s\+\)\{7\}\S\+\s\(\(daily\|weekly\|monthly\)\.[0-9][0-9]\?\)\$@\2@p" | \
     head -n1); \
   EC="$?"; \
else \
   echo "Destination directory '\'\\\'\'"${DST_PATH}"\'\\\'\'' does not exist."; \
   EC=-1; \
fi; \
if [ "$EC" -eq 0 ]; then \
   # If no current backup dir (first backup) \
   [ "$CUR" ] || CUR="'"$BU_TYPE"'"; \
   echo "$CUR"; \
else \
   ERR=true; \
fi; \
! "$ERR"  # return value'


function bucore {
  # Mount mount path
  if [ "$MNT_PATH" ]; then
    result=$(myexec 'mount "'"${MNT_PATH}"'"')
    [ "$?" -ne "0" ] && ERROR=true
  fi

  # Current backup dir
  if ! "$ERROR"; then           # If no previous error
    result=$(myexec "$curcmd")  # Does destination path exist?
    if [ "$?" -eq 0 ]; then
      CURRENT="$result"         # We successfully looked for the current backup
    else
      ERROR=true                # Dest path does not exist, or SSH problem
    fi
  fi

  if ! "$ERROR"; then  # If no previous error
    result=""
    TRIES=0
    while [ "$TRIES" -eq 0 ] || \
          ( [ \( "$SRC_HOST" -o "$DST_HOST" \) -a "$TRIES" -lt "$MAXTRIES" ] && \
          "$ERROR" ); do

      [ "$TRIES" -ne 0 ] && sleep "$SLEEPTIME"

      tmp=$(eval '/usr/bin/rsync --delete --delete-excluded -avz \
               --rsync-path /usr/bin/rsync -e "ssh -p'"${SSH_PORT}"' -i'"$HOME/.ssh/id_rsa"'" \
               '"$INCL_STR"' '"$EXCL_STR"' \
               --link-dest="'"../$CURRENT"'" \
               "'"${SRC_HOST}${SRC_SEP}${SRC_R_PATH}"'" "'"${DST_HOST}${DST_SEP}${DST_R_PATH}/$BU_TYPE"'"' 2>&1)
      [ "$?" -ne 0 -a "$?" -ne 24 ] && ERROR=true
      [ "$result" ] && result=$(echo -e "${result}\n--\n${tmp}") || result="$tmp"
      let TRIES+=1
    done
  fi


  if ! "$ERROR"; then           # If no previous error
    result=$(myexec 'set -e; cd "'"${DST_PATH}"'"; rm -f "current"; ln -s "'"$BU_TYPE"'" "current"; \
                     touch "'"$BU_TYPE"'"')
    [ "$?" -ne 0 ] && ERROR=true
  fi
}


function unlock {  # trapped to run on exit
  ECODE=1
  LOCKPID=$([ -f "$LOCKFILE" ] && cat "$LOCKFILE" || echo -1)
  if [ "$LOCKPID" ] && [ "$LOCKPID" -eq "$$" ]; then
    # Unmount mount path
    if [ "$MNT_PATH" ]; then
      MAXTRIES=1
      myexec 'umount "'"${MNT_PATH}"'"' >/dev/null
    fi
  rm -f "$LOCKFILE" 2>/dev/null
  ECODE=$?
  fi
  return $ECODE
}


# Separator (':') between rsync host and path if host defined
SRC_SEP=""
DST_SEP=""
[ "$SRC_HOST" ] && SRC_SEP=":"
[ "$DST_HOST" ] && DST_SEP=":"

# Escape '$' in remote rsync paths
if [ "$SRC_HOST" ]; then SRC_R_PATH=${SRC_PATH//$/\\$}; else SRC_R_PATH=${SRC_PATH}; fi
if [ "$DST_HOST" ]; then DST_R_PATH=${DST_PATH//$/\\$}; else DST_R_PATH=${DST_PATH}; fi

# Assemble --include and --exclude options to rsync
# Use eval to correctly parse quoted entries
EXCL_STR=
INCL_STR=
eval '\
set -f; \
for F in '"$EXCL"'; do \
  EXCL_STR="$EXCL_STR --exclude \"$F\""; \
done; \
for F in '"$INCL"'; do \
  INCL_STR="$INCL_STR --include \"$F\""; \
done; \
set +f'

# Day of the week (1..7)
DAY_W=`date "+%u"`

# Week of the month (1..5)
WEEK_M=$(( (10#`date "+%d"`-1)/7+1 ))

# Month of the year (1..12)
MONTH_Y=$(( 10#`date "+%m"` ))

# How long to keep spurious backups
MAX_DAYS=8
"$WEEKLY" && MAX_DAYS=32
"$MONTHLY" && MAX_DAYS=366

BU_TYPE="daily.$DAY_W"
if [ "$DAY_W" -eq 7 ]; then
   if "$MONTHLY" && [ "$WEEK_M" -eq 1 ]; then
     BU_TYPE="monthly.$MONTH_Y"
   elif "$WEEKLY"; then
       BU_TYPE="weekly.$WEEK_M"
  fi
fi

LOCKFILE="$LOCKDIR/$(basename -- "$0")"
trap "unlock; exit $?" INT TERM EXIT

TRYLOCK=true
ERROR=false

# Acquire lock
while "$TRYLOCK"; do
  if (set -o noclobber; echo "$$" > "$LOCKFILE") 2>/dev/null; then
    TRYLOCK=false                       # created new lock
    bucore
  else
    LOCKPID=$([ -f "$LOCKFILE" ] && cat "$LOCKFILE")
    if [ "$LOCKPID" ]; then
      if checkproc "$LOCKPID"; then     # lock process still exists
        TRYLOCK=false
        result="Failed to acquire '$LOCKFILE'. Held by '"$(cat "$LOCKFILE")"'."
        ERROR=true
      else
        rm -f "$LOCKFILE" 2>/dev/null   # stale lock file
      fi
    else
        result="Cannot access lock file '${LOCKFILE}'."
        TRYLOCK=false
        ERROR=true
    fi   
  fi
done

if [ "$DAY_W" -eq 7 ]; then
  EMAIL="$WKLY_EMAIL"
else
  EMAIL="$DYLY_EMAIL"
fi

if ! "$ERROR"; then

  # Remove all backup dirs beyond max time
  # (keep on one line to avoid csh [\\] vs. bash [\] newline escaping issues!)
  myexec 'find "'"${DST_PATH}"'" -maxdepth 1 -mtime "+'"$MAX_DAYS"'" -type d -regex ".*/\(daily\|weekly\|monthly\)\.[0-9][0-9]?$" -exec rm -rf {} \;' >/dev/null

  (
    echo -n "Remote backup completed successfully"
    [ "$TRIES" -ne 1 ] && echo " in $TRIES attempts." || echo "."
  ) | /bin/mail -s "${TITLE} SUCCESSFUL" "$EMAIL"
else
  (
   echo "Remote backup has failed."
   [ "$result" ]  && echo -e "\n$result"  | tr -d '\015'
  ) | /bin/mail -s "${TITLE} FAILED" "$WKLY_EMAIL"
fi