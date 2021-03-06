#!/usr/bin/env bash
# Script by Marianne M. Spiller <marianne.spiller@dfki.de>
# 20180118

PROG=`basename $0`
##---- Defining Icinga 2 exit states
STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3

##---- Ensure we're using GNU tools
DATE="/usr/gnu/bin/date"
GREP="/usr/gnu/bin/grep"
WC="/usr/gnu/bin/wc"

read -d '' USAGE <<- _EOF_
$PROG [ -c <critical_hours> ] [ -w <warning_hours> ] -d <dataset>
  -c : Optional: CRITICAL snapshot age in hours (default: 12h)
  -d : dataset to check"
  -w : Optional: WARNING snapshot age in hours (default: 6h)
_EOF_

_usage() {
  echo "$USAGE"
  exit $STATE_WARNING
}

_getopts() {
  while getopts 'c:d:hw:' OPT ; do
    case $OPT in
      c)
        CRITICAL_AGE="$OPTARG"
        ;;
      d)
        ZFS_DATASET="$OPTARG"
        ;;
      h)
        _usage
        exit $STATE_OK
        ;;
      w)
        WARNING_AGE="$OPTARG"
        ;;
     '')
        _usage
        break
        ;;
     *) echo "Invalid option --$OPTARG1"
        _usage
        exit $STATE_WARNING
        ;;
    esac
  done
}

_performance_data() {
cat <<- _EOF_
|last_ago=$DIFF;$WARNING_AGE_SECONDS;$CRITICAL_AGE_SECONDS;0;$CRITICAL_AGE_SECONDS; hourly=$COUNT_HOURLY;;;;; daily=$COUNT_DAILY;;;;; weekly=$COUNT_WEEKLY;;;;; monthly=$COUNT_MONTHLY;;;;; yearly=$COUNT_YEARLY;;;;;
_EOF_
}

_get_last_snapshot() {
  zfs list -r -t snapshot -o name -s creation $1|grep -v zrep|tail -n 1| tail -c 11
}

_count_all_snapshots() {
  zfs list -r -t snapshot -o name "$1"|$GREP -v zrep|tail +2|$WC -l
}

_count_snapshots() {
  zfs list -r -t snapshot -o name "$1"|$GREP -v zrep|$GREP "$2"|$WC -l
}

_getopts $@

if [ -z "$ZFS_DATASET" ] ; then
  echo "Please define ZFS dataset using -d <dataset> option"
  _usage
  exit $STATE_UNKNOWN
fi

if ! zfs list $ZFS_DATASET > /dev/null 2>&1; then
  echo "'$ZFS_DATASET' is not a ZFS dataset!"
  _usage
  exit $STATE_UNKNOWN
fi

if [ -z "$WARNING_AGE" ] ; then
  ## consider 6 hours when not explicitly set
  WARNING_AGE="6"
fi

if [ -z "$CRITICAL_AGE" ] ; then
  ## consider 12 hours when not explicitly set
  CRITICAL_AGE="12"
fi

CRITICAL_AGE_SECONDS=$(( $CRITICAL_AGE * 60 * 60 ))
WARNING_AGE_SECONDS=$(( $WARNING_AGE * 60 * 60 ))
NOW=$($DATE +%s)

##----------- Some statistics
COUNT_HOURLY=$(_count_snapshots $ZFS_DATASET hourly)
COUNT_DAILY=$(_count_snapshots $ZFS_DATASET daily)
COUNT_WEEKLY=$(_count_snapshots $ZFS_DATASET weekly)
COUNT_MONTHLY=$(_count_snapshots $ZFS_DATASET monthly)
COUNT_YEARLY=$(_count_snapshots $ZFS_DATASET yearly)

## Are there any snapshots at all for this dataset?
ARETHEREANY=$(_count_all_snapshots $ZFS_DATASET)
if [ $ARETHEREANY -eq 0 ] ; then
  echo "Absolutely no snapshots found for $ZFS_DATASET."
  exit $STATE_CRITICAL
fi

CREATION_DATE=$(_get_last_snapshot $ZFS_DATASET)
DIFF=$(( NOW - CREATION_DATE ))

##----------- Informational output follows
read -d '' FYI <<- _EOF_
Creation of last snapshot: $($DATE -d @$CREATION_DATE +%c) (timezone is $TZ)

  - $COUNT_HOURLY hourly snapshot(s) for $ZFS_DATASET
  - $COUNT_DAILY daily snapshot(s) for $ZFS_DATASET
  - $COUNT_WEEKLY weekly snapshot(s) for $ZFS_DATASET
  - $COUNT_MONTHLY monthly snapshot(s) for $ZFS_DATASET
  - $COUNT_YEARLY yearly snapshot(s) for $ZFS_DATASET
_EOF_

if [ "$DIFF" -gt "$CRITICAL_AGE_SECONDS" ] ; then
  echo "CRITICAL: last snapshot for $ZFS_DATASET is older than $CRITICAL_AGE hours - please check!"
  echo "$FYI"
  _performance_data
  exit $STATE_CRITICAL
elif [ "$DIFF" -gt "$WARNING_AGE_SECONDS" ] ; then
  echo "WARNING: got snapshot(s) for $ZFS_DATASET, but they are older than $WARNING_AGE hours."
  echo "$FYI"
  _performance_data
  exit $STATE_WARNING
else 
  echo "OK: got snapshot(s) for $ZFS_DATASET within the last $WARNING_AGE hours."
  echo "$FYI"
  _performance_data
  exit $STATE_OK
fi
