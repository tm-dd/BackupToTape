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

# settings
tapeDrive='/dev/nst0'
ddBlockSizeInMiB='1'
reserveBlocksForTapePartition='1'
mailSendTo='root'
logFolder="/root/tape_backups"

# files for logging the content
timeFileNamesOffset=`date +"%Y-%m-%d_%H-%M"`
logFile="${logFolder}/${timeFileNamesOffset}_tape_backup_notes.txt"
md5ChecksumFile="${logFolder}/${timeFileNamesOffset}_snapshot_md5sums.md5"
snapshotFileList="${logFolder}/${timeFileNamesOffset}_snapshot_content.txt"

# use log folder
mkdir -p "${logFolder}" || exit -1

# write all stdout and stderr also into a file
exec > >(tee "${logFile}") 2>&1

echo
echo "START BACKUP '$0 $@'"
echo

# check software
if [ -z "`which bzip2`" ]; then echo "missing software 'bzip2'"; ( set -x; apt install bzip2); fi
if [ -z "`which dd`" ]; then echo "missing software 'dd'";  ( set -x; apt install coreutils ); fi
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

# check if the snapshot exists and give some notes about the snapshot
/usr/sbin/zfs list -r -t snapshot "$1" -o name,refer,creation || exit -1
echo

# write the tapes
stopNow='no'
curTapeNumber=0
skipBlockNumbers=0
while [ "${stopNow}" != 'yes' ]
do
	echo
	echo "INSERT TAPE $((${curTapeNumber}+1)) TO WRITE the snapshot." | mail -s "insert tape $((${curTapeNumber}+1)) to the tape drive" ${mailSendTo}
	echo "INSERT TAPE $((${curTapeNumber}+1)) TO WRITE the snapshot."
	echo
	answer='n'
	while [ "${answer}" != "y" ]
	do
		echo -n "Are you ready (y/*) ? "
		read answer
	done
	echo

	( set -x; mt -f ${tapeDrive} rewind )
	echo

	echo "some information about tape in ${tapeDrive}"
	sg_read_attr ${tapeDrive} | grep 'Medium serial number\|MiB' || exit -1
	echo

	# calculate the number of blocks for the tape drive
	maxMiBOfTape=`sg_read_attr ${tapeDrive} | grep 'Remaining capacity in partition' | awk -F ': ' '{ print $2 }' || exit -1`
	byStartWrittenMiBOfTape=`sg_read_attr ${tapeDrive} | grep 'Total MiB written in current/last load' | awk -F ': ' '{ print $2 }' || exit -1`
	maxDdBlockNumbers=$(($((${maxMiBOfTape}/${ddBlockSizeInMiB}))-${reserveBlocksForTapePartition}))

	date

	echo
	echo -n "md5sum of the zfs snapshot to tape $((${curTapeNumber}+1)) by creating: " >> ${md5ChecksumFile}

	if [ "$2" = "" ]
	then
		# backup the full snapshot (second dd is nessesary to define the size of the input blocks and the maximal length of the pipe part for the tape and md5sum)
		echo "+ zfs send $1 | dd bs=${ddBlockSizeInMiB}M iflag=fullblock skip=${skipBlockNumbers} count=${maxDdBlockNumbers} 2> /dev/null | tee >( md5sum >> ${md5ChecksumFile} ) | dd bs=${ddBlockSizeInMiB}M of=${tapeDrive}"
		zfs send $1 | dd bs=${ddBlockSizeInMiB}M iflag=fullblock skip=${skipBlockNumbers} count=${maxDdBlockNumbers} 2> /dev/null | tee >( md5sum >> ${md5ChecksumFile} ) | dd bs=${ddBlockSizeInMiB}M of=${tapeDrive}
	else
		# backup the incremental snapshot (second dd is nessesary to define the size of the input blocks and the maximal length of the pipe part for the tape and md5sum)
		echo "+ set -x; zfs send -i $1 $2 | dd bs=${ddBlockSizeInMiB}M iflag=fullblock skip=${skipBlockNumbers} count=${maxDdBlockNumbers} 2> /dev/null | tee >( md5sum >> ${md5ChecksumFile} ) | dd bs=${ddBlockSizeInMiB}M of=${tapeDrive}"
		zfs send -i $1 $2 | dd bs=${ddBlockSizeInMiB}M iflag=fullblock skip=${skipBlockNumbers} count=${maxDdBlockNumbers} 2> /dev/null | tee >( md5sum >> ${md5ChecksumFile} ) | dd bs=${ddBlockSizeInMiB}M of=${tapeDrive}
	fi
	# short wait of the end of writing
	sleep 30
	echo
	date
	echo

	# because the value of 'Remaining capacity in partition' was not correct after writing in past, calculate the free size with the value of 'Total MiB written in current/last load'
	currentWrittenMiBOfTape=`sg_read_attr ${tapeDrive} | grep 'Total MiB written in current/last load' | awk -F ': ' '{ print $2 }'`
	lasttWrittenMiBOfTape=$((${currentWrittenMiBOfTape}-${byStartWrittenMiBOfTape}))
	skipBlockNumbers=$((${skipBlockNumbers}+${maxDdBlockNumbers}))
	freeMiBOfTape=$((${maxMiBOfTape}-${lasttWrittenMiBOfTape}))
	reserveMiBForTapes=$((${ddBlockSizeInMiB}*${reserveBlocksForTapePartition}))

	echo "The tape $((${curTapeNumber}+1)) was written ${lasttWrittenMiBOfTape} MiB. Read and check the content now ..." | mail -s "reading tape $((${curTapeNumber}+1))" ${mailSendTo}
	echo "The tape $((${curTapeNumber}+1)) was written ${lasttWrittenMiBOfTape} MiB. Read and check the content now ..."
	echo

	( set -x; mt -f ${tapeDrive} rewind )
	echo

	echo -n "md5sum of the zfs snapshot after reading tape $((${curTapeNumber}+1)) : " >> ${md5ChecksumFile}
	echo "+ dd if=${tapeDrive} bs=${ddBlockSizeInMiB}M | md5sum >> ${md5ChecksumFile}"
	dd if=${tapeDrive} bs=${ddBlockSizeInMiB}M | md5sum >> ${md5ChecksumFile}

	# short wait of the end of reading
	sleep 30
	echo
	date
	echo

	( set -x; mt -f ${tapeDrive} eject )
	echo

	# in the case the free MiB of the tape was bigger then the reserve MiB (after the last writing), stop the for loop because the backup should finished
	if [ ${freeMiBOfTape} -gt ${reserveMiBForTapes} ]
	then
		stopNow='yes'
	else
		# continute with next tape
		curTapeNumber=$((${curTapeNumber}+1))
	fi
done

echo "The backup could be finished now. Please check the files on '${logFolder}' later."

echo '
To restore the full backup you can try the following commands:

	mkfifo /tmp/pipe
	while sleep 1; do :; done > /tmp/pipe &
	pipe_pid=$!

	echo -n "How many tapes you have from this backup? "
	read numberOfTapes

	cat /tmp/pipe | zfs receive zfspool/restored &

	for ((curTapeNumber=0; ${curTapeNumber}<${numberOfTapes}; curTapeNumber++))
	do
		echo
		echo "INSERT TAPE $((${curTapeNumber}+1)) to RESTORE the snapshot."
		echo
		answer="n"
		while [ "$answer" != "y" ]
		do
			echo -n "Are you ready (y/*) ? "
			read answer
		done
		echo
		echo -n "tape $((${curTapeNumber}+1)) : " >> /tmp/restored.md5
		mt -f '${tapeDrive}' rewind
		dd if='${tapeDrive}' bs='${ddBlockSizeInMiB}'M | tee >( md5sum >> /tmp/restored.md5 ) > /tmp/pipe
		mt -f '${tapeDrive}' rewind
		mt -f '${tapeDrive}' eject
	done

	echo "md5sums of readed tapes:"
	cat /tmp/restored.md5

	kill $pipe_pid
	rm /tmp/pipe

Please note: If you plan to restore an incremental zfs snapshot after this restore, please restore it NOW and do not touch the older zfs snapshot before.
'

date
echo
echo "END OF BACKUP: $0 $mode $@"
echo
( set -x; cat ${md5ChecksumFile} )
echo

if [ "${snapshotFileList}" != "" ]
then
	( set -x; pwd; find . -type f -ls > "${snapshotFileList}"; wc -l "${snapshotFileList}"; bzip2 -9 "${snapshotFileList}"; ls -lh "${snapshotFileList}.bz2" )
	echo
fi

date
echo

cat "${logFile}" | mail -s "TAPE BACKUP FINISHED" ${mailSendTo}

exit 0
