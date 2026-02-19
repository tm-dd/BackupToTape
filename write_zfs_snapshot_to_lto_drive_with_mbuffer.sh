#!/bin/bash
#
# a basic script to write a zfs snapshot of an incremental zfs snapshot to a tape drive
#
# Copyright (c) 2026 tm-dd (Thomas Mueller) - https://github.com/tm-dd/BackupToTape
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
# IN THE SOFTWARE.
#

# settings
tapeDrive='/dev/nst0'
mailSendTo='root'
logFolder="/root/tape_backups"
mbufferLogFile='/tmp/mbuffer_tape_write.log'
mbufferBufferBlockSize='1M'
mbufferBufferSizeReservedBeforeStart='7G'
mbufferNeededPercentFillBeforeStart='80'
reserveMiBOnTape='1'

# files for logging the content
timeFileNamesOffset=`date +"%Y-%m-%d_%H-%M"`
logFile="${logFolder}/${timeFileNamesOffset}_tape_backup_notes.txt"
snapshotFileList="${logFolder}/${timeFileNamesOffset}_snapshot_content.txt"

# use log folder
mkdir -p "${logFolder}" || exit -1

# write all stdout and stderr also into a file
exec > >(tee "${logFile}") 2>&1

# check software
if [ -z "`which bzip2`" ]; then echo "missing software 'bzip2'"; ( set -x; apt install bzip2); fi
if [ -z "`which dd`" ]; then echo "missing software 'dd'";  ( set -x; apt install coreutils ); fi
if [ -z "`which mbuffer`" ]; then echo "missing software 'mbuffer'"; ( set -x; apt install mbuffer); fi
if [ -z "`which md5sum`" ]; then echo "missing software 'md5sum'"; ( set -x; apt install tar ); fi
if [ -z "`which sg_read_attr`" ]; then echo "missing software 'sg_read_attr' to read the serial number of the tape"; ( set -x; apt install sg3-utils ); fi
if [ -z "`which tee`" ]; then echo "missing software 'tee'"; ( set -x; apt install tar ); fi

# check parameters
if [ -z "${1}" ]
then
	echo
	echo "USAGE: $0 zfsppol/zfsvolume@snapshot1                               # to backup the full ZFS snapshot 'snapshot1'"
	echo "USAGE: $0 zfsppol/zfsvolume@snapshot1 zfsppol/zfsvolume@snapshot2   # to backup the differences between ZFS snapshot 'snapshot1' and 'snapshot2'"
	echo
	exit -1
fi

echo
( set -x; mt -f ${tapeDrive} rewind )
echo
echo "some information about the first tape in ${tapeDrive}"
sg_read_attr ${tapeDrive} | grep 'Medium serial number\|MiB' || exit -1
echo

# calculate the number of blocks for the tape drive
maxMiBOfTape=`sg_read_attr ${tapeDrive} | grep 'Remaining capacity in partition' | awk -F ': ' '{ print $2 }' || exit -1`
maxMiBToReadForMbuffer=$((${maxMiBOfTape}-${reserveMiBOnTape}))

# start the backup
date
echo
if [ "$2" = "" ]
then 
	echo "START NEW FULL BACKUP '$0 $@'"
	echo
	# backup the full snapshot
	echo "+ zfs send $1 | mbuffer -s ${mbufferBufferBlockSize} -A \"echo; echo -n 'INSERT NEXT TAPE AND PRESS ENTER'; echo 'INSERT NEXT TAPE ON $HOSTNAME AND PRESS ENTER' | mail -s 'insert new tape' $mailSendTo; read temp < /dev/tty; echo; date\" -m ${mbufferBufferSizeReservedBeforeStart} -P ${mbufferNeededPercentFillBeforeStart} -D ${maxMiBToReadForMbuffer}M -l ${mbufferLogFile} -q -o ${tapeDrive}"
	zfs send $1 | mbuffer -s ${mbufferBufferBlockSize} -A "echo; echo -n 'INSERT NEXT TAPE AND PRESS ENTER'; echo 'INSERT NEXT TAPE ON $HOSTNAME AND PRESS ENTER' | mail -s 'insert new tape' $mailSendTo; read temp < /dev/tty; echo; date" -m ${mbufferBufferSizeReservedBeforeStart} -P ${mbufferNeededPercentFillBeforeStart} -D ${maxMiBToReadForMbuffer}M -l ${mbufferLogFile} -q -o ${tapeDrive}
else
	echo "START NEW INCREMENTAL BACKUP '$0 $@'"
	echo
	# backup the incremental snapshot (second dd is nessesary to define the size of the input blocks and the maximal length of the pipe part for the tape and md5sum)
	echo "+ zfs send -i $1 $2 | mbuffer -s ${mbufferBufferBlockSize} -A \"echo; echo -n 'INSERT NEXT TAPE AND PRESS ENTER'; echo 'INSERT NEXT TAPE ON $HOSTNAME AND PRESS ENTER' | mail -s 'insert new tape' $mailSendTo; read temp < /dev/tty; echo; date\" -m ${mbufferBufferSizeReservedBeforeStart} -P ${mbufferNeededPercentFillBeforeStart} -D ${maxMiBToReadForMbuffer}M -l ${mbufferLogFile} -q -o ${tapeDrive}"
	zfs send -i $1 $2 | mbuffer -s ${mbufferBufferBlockSize} -A "echo; echo -n 'INSERT NEXT TAPE AND PRESS ENTER'; echo 'INSERT NEXT TAPE ON $HOSTNAME AND PRESS ENTER' | mail -s 'insert new tape' $mailSendTo; read temp < /dev/tty; echo; date" -m ${mbufferBufferSizeReservedBeforeStart} -P ${mbufferNeededPercentFillBeforeStart} -D ${maxMiBToReadForMbuffer}M -l ${mbufferLogFile} -q -o ${tapeDrive}
fi

echo "The backup could be finished now. Please check the files on '${logFolder}' later."

echo
date

echo '
To restore the full backup you can try the folowing commands:

   By using a snapshot on only one tape:

      mt -f '${tapeDrive}' rewind

      mbuffer -i '${tapeDrive}' -s '${mbufferBufferBlockSize}' -m '${mbufferBufferSizeReservedBeforeStart}' -P '${mbufferNeededPercentFillBeforeStart}' -l '${mbufferLogFile}' | zfs receive zfspool/restored

      mt -f '${tapeDrive}' rewind
      mt -f '${tapeDrive}' eject

   The backup should be restored now.

   By using a snapshot on more than one tape:

      mkfifo /tmp/pipe
      while sleep 1; do :; done > /tmp/pipe &
      pipe_pid=$!

      cat /tmp/pipe | zfs receive zfspool/restored &

   Than do for every tape this steps:

      mt -f '${tapeDrive}' rewind

      mbuffer -i '${tapeDrive}' -s '${mbufferBufferBlockSize}' -m '${mbufferBufferSizeReservedBeforeStart}' -P '${mbufferNeededPercentFillBeforeStart}' -l '${mbufferLogFile}' > /tmp/pipe

      mt -f '${tapeDrive}' rewind
      mt -f '${tapeDrive}' eject

   After the last tape do:

      kill $pipe_pid
      rm /tmp/pipe

   The backup should be restored now.

Please note: If you plan to restore an incremental zfs snapshot after this restore, please restore it NOW and do not touch the older zfs snapshot.
'

date
echo
echo "END OF BACKUP: $0 $mode $@"
echo

if [ "${snapshotFileList}" != "" ]
then
	( set -x; pwd; find . -type f -ls > "${snapshotFileList}"; wc -l "${snapshotFileList}"; bzip2 -9 "${snapshotFileList}"; ls -lh "${snapshotFileList}.bz2" )
	echo
fi

date
echo

cat "${logFile}" | mail -s "tape BACKUP FINISHED" ${mailSendTo}

exit 0
