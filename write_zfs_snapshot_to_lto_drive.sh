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
# NOTE: the hint with keeping of the pipe was found on https://unix.stackexchange.com/questions/366219/prevent-automatic-eofs-to-a-named-pipe-and-send-an-eof-when-i-want-it
#

#
# settings (DO NOT USE WHITE SPACES IN THE FILE NAMES.)
#

tapeDrive='/dev/nst0'
mailSendTo='root'
reserveMiBOnTape='1'
mbufferBufferBlockSize='1M'
mbufferBufferSizeReservedBeforeStart='7G'
mbufferNeededPercentFillBeforeStart='80'
mbufferLogFile1='/tmp/mbuffer_tape_writing.log'
mbufferLogFile2='/tmp/mbuffer_tape_reading.log'
pipeForMd5sum='/tmp/tapechecker'
logFolder='/root/tape_backups'
timeFileNamesOffset=`date +'%Y-%m-%d_%H-%M'`
logFile="${logFolder}/${timeFileNamesOffset}_tape_backup_notes.txt"
checksumFileWrited="${logFolder}/${timeFileNamesOffset}_snapshot_md5sums_writed.md5"
checksumFileReaded="${logFolder}/${timeFileNamesOffset}_snapshot_md5sums_readed.md5"
snapshotFileList="${logFolder}/${timeFileNamesOffset}_snapshot_content.txt"

# check software
if [ -z "`which bzip2`" ]; then echo "missing software 'bzip2'"; ( set -x; apt install bzip2); fi
if [ -z "`which mbuffer`" ]; then echo "missing software 'mbuffer'"; ( set -x; apt install mbuffer); fi
if [ -z "`which md5sum`" ]; then echo "missing software 'md5sum'"; exit -1; fi
if [ -z "`which pigz`" ]; then echo "missing software 'pigz'"; ( set -x; apt install pigz ); fi
if [ -z "`which pixz`" ]; then echo "missing software 'pixz'"; ( set -x; apt install pixz ); fi
if [ -z "`which sg_read_attr`" ]; then echo "missing software 'sg_read_attr' to read the serial number of the tape"; ( set -x; apt install sg3-utils ); fi
if [ -z "`which tee`" ]; then echo "missing software 'tee'"; ( set -x; apt install coreutils ); fi

# use log folder
mkdir -p "${logFolder}" || exit -1

# write all stdout and stderr also into a file
exec > >(tee "${logFile}") 2>&1

# check parameters
if [ -z "$2" ]
then
	echo
	echo "USAGE: $0 COMPRESS zfsppol/zfsvolume@snapshot1"
	echo "USAGE: $0 COMPRESS zfsppol/zfsvolume@snapshot1 zfsppol/zfsvolume@snapshot2"
	echo "options for COMPRESS: none gz[1..9] xz[0..9]"
	echo
	echo "Example write the ZFS snapshot 'snapshot1' without compression to the tape drive. : $0 none zfsppol/zfsvolume@snapshot1"
	echo "Example write the differential snapshot from 'snapshot1' to 'snapshot2' compressed: $0 gz5  zfsppol/zfsvolume@snapshot1 zfsppol/zfsvolume@snapshot2  "
	echo
	sleep 1
	exit -1
fi

echo
( set -x; mt -f ${tapeDrive} rewind )
echo
echo "some information about the first tape in ${tapeDrive}"
sg_read_attr ${tapeDrive} | grep 'Medium serial number\|MiB' || exit -1
echo

# check if the snapshot exists and give notes
/usr/sbin/zfs list -r -t snapshot "$2" -o name,refer,creation || exit -1
echo
echo "Check the log files ${mbufferLogFile1} (for writing) and ${mbufferLogFile2} (for reading) durring the backup process."
echo

# start the checksum files
echo -n "md5sum of the zfs snapshot to tape by creating: " > "${checksumFileWrited}"
echo -n "md5sum of the zfs snapshot to tape by reading:  " > "${checksumFileReaded}"

# set the compression and decompression pipe commands
compression=''
decompression=''
case "$1" in
	none) compression='cat'; decompression='cat' ;;
	gz1)  compression='pigz -1' ; decompression='pigz -d' ;;
	gz2)  compression='pigz -2' ; decompression='pigz -d' ;;
	gz3)  compression='pigz -3' ; decompression='pigz -d' ;;
	gz4)  compression='pigz -4' ; decompression='pigz -d' ;;
	gz5)  compression='pigz -5' ; decompression='pigz -d' ;;
	gz6)  compression='pigz -6' ; decompression='pigz -d' ;;
	gz7)  compression='pigz -7' ; decompression='pigz -d' ;;
	gz8)  compression='pigz -8' ; decompression='pigz -d' ;;
	gz9)  compression='pigz -9' ; decompression='pigz -d' ;;
	xz0)  compression='pixz -0' ; decompression='pixz -d' ;;
	xz1)  compression='pixz -1' ; decompression='pixz -d' ;;
	xz2)  compression='pixz -2' ; decompression='pixz -d' ;;
	xz3)  compression='pixz -3' ; decompression='pixz -d' ;;
	xz4)  compression='pixz -4' ; decompression='pixz -d' ;;
	xz5)  compression='pixz -5' ; decompression='pixz -d' ;;
	xz6)  compression='pixz -6' ; decompression='pixz -d' ;;
	xz7)  compression='pixz -7' ; decompression='pixz -d' ;;
	xz8)  compression='pixz -8' ; decompression='pixz -d' ;;
	xz9)  compression='pixz -9' ; decompression='pixz -d' ;;
	*) echo -e "\n!!! WRONG MODE !!!"; $0; exit -1 ;;
esac
if [ "$1" != "none" ]
then
	echo "compression command   : ${compression}"
	echo "decompression command : ${decompression}"
fi

# create a pipe for the reading of all tapes later
if [ -e "${pipeForMd5sum}" ]; then echo; ( set -x; rm "${pipeForMd5sum}"; sleep 1 ); fi
mkfifo "${pipeForMd5sum}"
while sleep 1; do :; done > "${pipeForMd5sum}" &
pipeForMd5sumPid=$!
md5sum "${pipeForMd5sum}" >> "${checksumFileReaded}" &
sleep 3

# start the backup
echo
date
echo
if [ "$3" = "" ]
then 
	echo "START NEW FULL BACKUP '$0 $@'"
	echo
	# backup the full snapshot (hint: the checksum from mbuffer is from the compressed not from the uncompressed stream)
	echo "+ zfs send $2 | ${compression} | mbuffer --md5 -s ${mbufferBufferBlockSize} -A \"tail -n 1 ${mbufferLogFile1}; echo; date; echo; echo 'reading tape ...'; mt -f ${tapeDrive} rewind; mbuffer -i '${tapeDrive}' -s '${mbufferBufferBlockSize}' -m '${mbufferBufferSizeReservedBeforeStart}' -P '${mbufferNeededPercentFillBeforeStart}' -q -l ${mbufferLogFile2} >> ${pipeForMd5sum}; echo; tail -n 1 ${mbufferLogFile2}; echo; date; echo; echo '---'; echo; echo -n 'INSERT NEXT TAPE AND PRESS ENTER'; echo 'INSERT NEXT TAPE ON $HOSTNAME AND PRESS ENTER' | mail -s 'insert new tape' $mailSendTo; read temp < /dev/tty; echo; echo 'some information about the next tape in ${tapeDrive}'; sg_read_attr ${tapeDrive} | grep 'Medium serial number\|MiB'; echo; date; echo; echo 'writing next tape ...'; echo\" -m ${mbufferBufferSizeReservedBeforeStart} -P ${mbufferNeededPercentFillBeforeStart} -l ${mbufferLogFile1} -q -o ${tapeDrive}"
	zfs send $2 | ${compression} | mbuffer --md5 -s ${mbufferBufferBlockSize} -A "tail -n 1 ${mbufferLogFile1}; echo; date; echo; echo 'reading tape ...'; mt -f ${tapeDrive} rewind; mbuffer -i '${tapeDrive}' -s '${mbufferBufferBlockSize}' -m '${mbufferBufferSizeReservedBeforeStart}' -P '${mbufferNeededPercentFillBeforeStart}' -q -l ${mbufferLogFile2} >> ${pipeForMd5sum}; echo; tail -n 1 ${mbufferLogFile2}; echo; date; echo; echo '---'; echo; echo -n 'INSERT NEXT TAPE AND PRESS ENTER'; echo 'INSERT NEXT TAPE ON $HOSTNAME AND PRESS ENTER' | mail -s 'insert new tape' $mailSendTo; read temp < /dev/tty; echo; echo 'some information about the next tape in ${tapeDrive}'; sg_read_attr ${tapeDrive} | grep 'Medium serial number\|MiB'; echo; date; echo; echo 'writing next tape ...'; echo" -m ${mbufferBufferSizeReservedBeforeStart} -P ${mbufferNeededPercentFillBeforeStart} -l ${mbufferLogFile1} -q -o ${tapeDrive}
else
	echo "START NEW INCREMENTAL BACKUP '$0 $@'"
	echo
	# backup the incremental snapshot (hint: the checksum from mbuffer is from the compressed not from the uncompressed stream)
	echo "+ zfs send -i $2 $3 | ${compression} | mbuffer --md5 -s ${mbufferBufferBlockSize} -A \"tail -n 1 ${mbufferLogFile1}; echo; date; echo; echo 'reading tape ...'; mt -f ${tapeDrive} rewind; mbuffer -i '${tapeDrive}' -s '${mbufferBufferBlockSize}' -m '${mbufferBufferSizeReservedBeforeStart}' -P '${mbufferNeededPercentFillBeforeStart}' -q -l ${mbufferLogFile2} >> ${pipeForMd5sum}; echo; tail -n 1 ${mbufferLogFile2}; echo; date; echo; echo '---'; echo; echo -n 'INSERT NEXT TAPE AND PRESS ENTER'; echo 'INSERT NEXT TAPE ON $HOSTNAME AND PRESS ENTER' | mail -s 'insert new tape' $mailSendTo; read temp < /dev/tty; echo; echo 'some information about the next tape in ${tapeDrive}'; sg_read_attr ${tapeDrive} | grep 'Medium serial number\|MiB'; echo; date; echo; echo 'writing next tape ...'; echo\" -m ${mbufferBufferSizeReservedBeforeStart} -P ${mbufferNeededPercentFillBeforeStart} -l ${mbufferLogFile1} -q -o ${tapeDrive}"
	zfs send -i $2 $3 | ${compression} | mbuffer --md5 -s ${mbufferBufferBlockSize} -A "tail -n 1 ${mbufferLogFile1}; echo; date; echo; echo 'reading tape ...'; mt -f ${tapeDrive} rewind; mbuffer -i '${tapeDrive}' -s '${mbufferBufferBlockSize}' -m '${mbufferBufferSizeReservedBeforeStart}' -P '${mbufferNeededPercentFillBeforeStart}' -q -l ${mbufferLogFile2} >> ${pipeForMd5sum}; echo; tail -n 1 ${mbufferLogFile2}; echo; date; echo; echo '---'; echo; echo -n 'INSERT NEXT TAPE AND PRESS ENTER'; echo 'INSERT NEXT TAPE ON $HOSTNAME AND PRESS ENTER' | mail -s 'insert new tape' $mailSendTo; read temp < /dev/tty; echo; echo 'some information about the next tape in ${tapeDrive}'; sg_read_attr ${tapeDrive} | grep 'Medium serial number\|MiB'; echo; date; echo; echo 'writing next tape ...'; echo" -m ${mbufferBufferSizeReservedBeforeStart} -P ${mbufferNeededPercentFillBeforeStart} -l ${mbufferLogFile1} -q -o ${tapeDrive}

fi
grep ' hash:' ${mbufferLogFile1} >> "${checksumFileWrited}"
tail -n 1 ${mbufferLogFile1}
echo
date
echo
echo 'reading last tape ...'
mt -f ${tapeDrive} rewind
mbuffer -i "${tapeDrive}" -s "${mbufferBufferBlockSize}" -m "${mbufferBufferSizeReservedBeforeStart}" -P "${mbufferNeededPercentFillBeforeStart}" -q -l "${mbufferLogFile2}" >> "${pipeForMd5sum}"
mt -f ${tapeDrive} rewind
mt -f ${tapeDrive} eject
echo
tail -n 1 ${mbufferLogFile2}
echo
date
echo

# end the pipe of reading
kill ${pipeForMd5sumPid}
sleep 5
rm -v "${pipeForMd5sum}"
echo

echo "The backup could be finished now. Please check the files on '${logFolder}' later."

echo
date

echo '
To restore the full backup you can try the folowing commands:

   By using a snapshot on only one tape:

      mt -f '${tapeDrive}' rewind

      mbuffer --md5 -i '${tapeDrive}' -s '${mbufferBufferBlockSize}' -m '${mbufferBufferSizeReservedBeforeStart}' -P '${mbufferNeededPercentFillBeforeStart}' -l '${mbufferLogFile2}' | '${decompression}' | zfs receive zfspool/restored

      mt -f '${tapeDrive}' rewind
      mt -f '${tapeDrive}' eject

   The backup should then be restored.

   By using a snapshot on more than one tape:

      mkfifo /tmp/pipe
      while sleep 1; do :; done > /tmp/pipe &
      pipe_pid=$!

      cat /tmp/pipe | '${decompression}' | zfs receive zfspool/restored &

   Than do for every tape this steps:

      mt -f '${tapeDrive}' rewind

      mbuffer -i '${tapeDrive}' -s '${mbufferBufferBlockSize}' -m '${mbufferBufferSizeReservedBeforeStart}' -P '${mbufferNeededPercentFillBeforeStart}' -l '${mbufferLogFile2}' > /tmp/pipe

      mt -f '${tapeDrive}' rewind
      mt -f '${tapeDrive}' eject

   After the last tape do:

      kill $pipe_pid
      rm /tmp/pipe

   The backup should then be restored.

Please note: If you plan to restore an incremental zfs snapshot after this restore, please restore it NOW and do not touch the restored zfs file system before.
Hint 1: The command "zfs receive" will be check the data by restoring and stop, if there was something wrong with the backup file.
Hint 2: A message like "can not seek in input: Illegal seek" during a restore process cat be ignored.
'

date
echo
echo "END OF BACKUP: $0 $mode $@"
echo
( set -x; cat "${checksumFileWrited}" "${checksumFileReaded}" )
echo

# create a file list of the snapshot
if [ "${snapshotFileList}" != "" ]
then
	volumenName=`echo "$2" | awk -F '@' '{ print $1 }'`
	if [ "$3" = "" ]
	then
		snapshotName=`echo "$2" | awk -F '@' '{ print $2 }'`
		snapshotMountPoint="`mount | grep '${volumenName}' | awk -F ' ' '{ print $3 }'`/${volumenName}/.zfs/snapshot/${snapshotName}"
	else
		snapshotName=`echo "$3" | awk -F '@' '{ print $2 }'`
		snapshotMountPoint="`mount | grep '${volumenName}' | awk -F ' ' '{ print $3 }'`/${volumenName}/.zfs/snapshot/${snapshotName}"
	fi
	cd "${snapshotMountPoint}"
	if [ -d "${snapshotMountPoint}" ]
	then
		echo "creating file list ..."
		echo
		( set -x; pwd; find . -type f -ls > "${snapshotFileList}"; wc -l "${snapshotFileList}"; bzip2 -9 "${snapshotFileList}"; ls -lh "${snapshotFileList}.bz2" )
	fi
	echo
fi

date
echo

cat "${logFile}" | mail -s "tape BACKUP FINISHED" ${mailSendTo}

exit 0
