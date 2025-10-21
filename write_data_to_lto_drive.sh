#!/bin/bash
#
# a basic script to write data to a tape drive
#
# Copyright (c) 2025 tm-dd (Thomas Mueller) - https://github.com/tm-dd/BackupToTape
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
tarCreateOptions="-c --blocking-factor=2048"
tarReadOptions="-v --blocking-factor=2048"
ddBlockSize='1M'
createCheckSumFile='y'
createContenFile='y'
ejectTapeAtWriteEnd='y'
mailSendTo='root'
logFolder="/root/tape_backups"

# files for logging the content
timeFileNamesOffset=`date +"%Y-%m-%d_%H-%M"`
logFile="${logFolder}/${timeFileNamesOffset}_tape_backup_notes.txt"
tapeContentFile="${logFolder}/${timeFileNamesOffset}_tape_backup_content.txt"
md5ChecksumFile="${logFolder}/${timeFileNamesOffset}_tape_backup_checksums.md5"

# use log folder
mkdir -p "${logFolder}" || exit -1

# write all stdout and stderr also into a file
exec > >(tee "${logFile}") 2>&1

# check software
if [ -z "`which tar`" ]; then echo "missing software 'tar'"; ( set -x; apt install tar ); fi
if [ -z "`which sg_read_attr`" ]; then echo "miss software 'sg_read_attr' to read the serial number of the tape"; ( set -x; apt install sg3-utils ); fi
if [ -z "`which dd`" ]; then echo "missing software 'dd'";  ( set -x; apt install coreutils ); fi
if [ -z "`which pigz`" ]; then echo "missing software 'pigz'"; ( set -x; apt install pigz ); fi
if [ -z "`which 7za`" ]; then echo "missing software '7za'"; ( set -x; apt install p7zip-full); fi
if [ -z "`which parallel`" ]; then echo "missing software 'parallel'"; ( set -x; apt install parallel ); fi


# check parameters
if [ -z "${2}" ]
then
	echo
	echo "USAGE: $0 METHOD tobackup1 [tobackup2] [...]"
	echo "METHODs: tar targz[1..9] tarxz[1..11]dd"
	echo
	echo "EXAMPLE: $0 tarxz3dd /etc /home"
	echo
	echo 'Please note the following information:
- In the case that the backup was using tar with the option "--blocking-factor", please use the same option and value for the restore process.
- The command tar do not create checksums for the data of the files in the tar archive. To be sure, that the content of the backup could be OK, please write the checksum file (option $createCheckSumFile) to the backup.
- In the fist part of the tape you find the backups and if configured, the checksum file "'${md5ChecksumFile}'". 
- In the second part you can find the bzip compressed text file "'${tapeContentFile}'", if configured, with the file names read from the backup of the tape.
- Sometimes we had trouble by using "mt -f '${tapeDrive}' rsf 1". Better rewind to the start of the tape and use "mt -f '${tapeDrive}' fsf ..." to go to the nessesary part of the tape.
- To restore a file of a tape it could be nessesary to read very long time for finding the start of the file on the tape.
'
	echo
	exit -1
fi
mode="${1}"
shift
case "${mode}" in
	tar) echo "WRITE TAPE WITHOUT ANY COMPRESSION.";;
	targz1|targz2|targz3|targz4|targz5|targz6|targz7|targz8|targz9|tarxz1dd|tarxz2dd|tarxz3dd|tarxz4dd|tarxz5dd|tarxz6dd|tarxz7dd|tarxz8dd|tarxz9dd|tarxz10dd|tarxz11dd) echo "WRITE TAPE WITH THE COMPRESSION OPTION ${mode}.";;
	*) echo -e "\n!!! ERROR, WRONG MODE. !!!"; $0; exit -1 ;;
esac

echo
echo "start of: $0 $mode $@"
echo
date
echo
(set -x; pwd)
echo

echo "some information about tape in ${tapeDrive}"
sg_read_attr ${tapeDrive} | grep 'Medium serial number\|MiB' || exit -1
echo

echo "rewind ${tapeDrive}"
( set -x; mt -f ${tapeDrive} rewind )
( set -x; mt -f ${tapeDrive} status )
echo

numOfFiles='unknown number of'

echo "checking the size of the backup data"
fullSizeInMegaByte=0
for lineInGigaByte in `du -s -BM $@ 2> /dev/null | awk '{ print $1 }' | sed 's/M$//'`
do
	fullSizeInMegaByte=$((${lineInGigaByte}+${fullSizeInMegaByte}))
done
echo
date
echo

ratio=0
maxMiBOfTape=`sg_read_attr ${tapeDrive} | grep 'Maximum capacity in partition' | awk -F ': ' '{ print $2 }' || exit -1`
ratio=$((${fullSizeInMegaByte}*100/${maxMiBOfTape}))
if [ $ratio -gt 97 ] && [ "$mode" != "tar" ]
then 
	echo -e "\nWARNING: MAYBE TO MUCH DATA FOR ONLY ONE TAPE WITH ${maxMiBOfTape} MiB. STOP HERE.\nPlease use the uncompressed MODE 'tar' and use the option '--multi-volume' or split the backup.\n"
	exit -1
else
	echo -e "\nThis should take around ${ratio}% capacity of the tape.\n"
fi

if [ $ratio -gt 100 ] && [ "$mode" = "tar" ]
then
	echo -e "The current backup can take around `echo $(($ratio/100+1))` tapes for the about ${fullSizeInMegaByte} MB of data." | mail -s "Note: The current backup can take more the one volumes." ${mailSendTo}
fi

# create a checksum file, if "${createCheckSumFile}" was 'y' in the settings
if [ "${createCheckSumFile}" = 'y' ]
then
	rm -f "${md5ChecksumFile}"
	echo "CREATE CHECKSUM FILE '${md5ChecksumFile}' for a later file integrity check for the files (in total about ${fullSizeInMegaByte} MB) on the backup. This can take a lot of time."
	echo "CREATE CHECKSUM FILE '${md5ChecksumFile}' for a later file integrity check for the files (in total about ${fullSizeInMegaByte} MB) on the backup. This can take a lot of time." | mail -s "start creating checksum file for the new tape backup" ${mailSendTo}
	if [ -n "`which parallel`" ]
	then
		find $@ -type f | parallel -j 16 md5sum > "${md5ChecksumFile}"
	else
		find $@ -type f -exec md5sum {} + > "${md5ChecksumFile}"
	fi
	ls -l "${md5ChecksumFile}"
	numOfFiles=`wc -l "${md5ChecksumFile}" | awk '{ print $1 }'`
	echo
	date
	echo
fi

serialNumberOfFirstTape=`sg_read_attr /dev/nst0 | grep 'Medium serial number' | awk -F ': ' '{ print $2 }'`

# write the data to the tape
echo "WRITE the content of ${fullSizeInMegaByte} megamytes (and some more) with ${numOfFiles} files to the TAPE drive."
echo "WRITE the content of ${fullSizeInMegaByte} megabytes (and some more) with ${numOfFiles} files to the TAPE drive." | mail -s "start writing data to the tape drive" ${mailSendTo}
case "${mode}" in
	tar) (set -x; tar --multi-volume ${tarCreateOptions} -f ${tapeDrive} ${md5ChecksumFile} $@);;
	targz1) (set -x; tar --use-compress-program='pigz -1 -r' ${tarCreateOptions} -f ${tapeDrive} ${md5ChecksumFile} $@);;
	targz2) (set -x; tar --use-compress-program='pigz -2 -r' ${tarCreateOptions} -f ${tapeDrive} ${md5ChecksumFile} $@);;
	targz3) (set -x; tar --use-compress-program='pigz -3 -r' ${tarCreateOptions} -f ${tapeDrive} ${md5ChecksumFile} $@);;
	targz4) (set -x; tar --use-compress-program='pigz -4 -r' ${tarCreateOptions} -f ${tapeDrive} ${md5ChecksumFile} $@);;
	targz5) (set -x; tar --use-compress-program='pigz -5 -r' ${tarCreateOptions} -f ${tapeDrive} ${md5ChecksumFile} $@);;
	targz6) (set -x; tar --use-compress-program='pigz -6 -r' ${tarCreateOptions} -f ${tapeDrive} ${md5ChecksumFile} $@);;
	targz7) (set -x; tar --use-compress-program='pigz -7 -r' ${tarCreateOptions} -f ${tapeDrive} ${md5ChecksumFile} $@);;
	targz8) (set -x; tar --use-compress-program='pigz -8 -r' ${tarCreateOptions} -f ${tapeDrive} ${md5ChecksumFile} $@);;
	targz9) (set -x; tar --use-compress-program='pigz -9 -r' ${tarCreateOptions} -f ${tapeDrive} ${md5ChecksumFile} $@);;
	tarxz1dd) (set -x; tar ${tarCreateOptions} ${md5ChecksumFile} $@ | 7za a -txz -an -bd -si -so -mx=1 | dd of=${tapeDrive} bs=${ddBlockSize});;
	tarxz2dd) (set -x; tar ${tarCreateOptions} ${md5ChecksumFile} $@ | 7za a -txz -an -bd -si -so -mx=2 | dd of=${tapeDrive} bs=${ddBlockSize});;
	tarxz3dd) (set -x; tar ${tarCreateOptions} ${md5ChecksumFile} $@ | 7za a -txz -an -bd -si -so -mx=3 | dd of=${tapeDrive} bs=${ddBlockSize});;
	tarxz4dd) (set -x; tar ${tarCreateOptions} ${md5ChecksumFile} $@ | 7za a -txz -an -bd -si -so -mx=4 | dd of=${tapeDrive} bs=${ddBlockSize});;
	tarxz5dd) (set -x; tar ${tarCreateOptions} ${md5ChecksumFile} $@ | 7za a -txz -an -bd -si -so -mx=5 | dd of=${tapeDrive} bs=${ddBlockSize});;
	tarxz6dd) (set -x; tar ${tarCreateOptions} ${md5ChecksumFile} $@ | 7za a -txz -an -bd -si -so -mx=6 | dd of=${tapeDrive} bs=${ddBlockSize});;
	tarxz7dd) (set -x; tar ${tarCreateOptions} ${md5ChecksumFile} $@ | 7za a -txz -an -bd -si -so -mx=7 | dd of=${tapeDrive} bs=${ddBlockSize});;
	tarxz8dd) (set -x; tar ${tarCreateOptions} ${md5ChecksumFile} $@ | 7za a -txz -an -bd -si -so -mx=8 | dd of=${tapeDrive} bs=${ddBlockSize});;
	tarxz9dd) (set -x; tar ${tarCreateOptions} ${md5ChecksumFile} $@ | 7za a -txz -an -bd -si -so -mx=9 | dd of=${tapeDrive} bs=${ddBlockSize});;
	tarxz10dd) (set -x; tar ${tarCreateOptions} ${md5ChecksumFile} $@ | 7za a -txz -an -bd -si -so -mx=10 | dd of=${tapeDrive} bs=${ddBlockSize});;
	tarxz11dd) (set -x; tar ${tarCreateOptions} ${md5ChecksumFile} $@ | 7za a -txz -an -bd -si -so -mx=11 | dd of=${tapeDrive} bs=${ddBlockSize});;
	*) echo -e "\n!!! WRONG MODE !!!"; $0; exit -1 ;;
esac
echo
( set -x; mt -f ${tapeDrive} status | grep 'file number =' )
echo
date
echo

serialNumberOfCurrentTape=`sg_read_attr /dev/nst0 | grep 'Medium serial number' | awk -F ': ' '{ print $2 }'`

if [ "${createContenFile}" = "y" ]
then

	# change tape to tape number one, if more the one tape was written
	if [ "${serialNumberOfFirstTape}" != "${serialNumberOfCurrentTape}" ]
	then
		( set -x; mt -f ${tapeDrive} rewind )
		echo -n "Insert tape 1 and press return to read the content of the tape:"
		read
	fi

	# read the tape
	echo "READ backup from TAPE and write the list of content to the file '${tapeContentFile}'."
	echo "READ backup from TAPE and write the list of content to the file '${tapeContentFile}'." | mail -s "start reading data from the tape drive" ${mailSendTo}
	echo
	( set -x; mt -f ${tapeDrive} rewind )
	( set -x; mt -f ${tapeDrive} status | grep 'file number =' )
	echo
	case "${mode}" in
		tar) (set -x; tar -f ${tapeDrive} ${tarReadOptions} -t > "${tapeContentFile}");;
		targz1|targz2|targz3|targz4|targz5|targz6|targz7|targz8|targz9) (set -x; dd if=${tapeDrive} bs=${ddBlockSize} | pigz -d | tar ${tarReadOptions} -t > "${tapeContentFile}");;
		tarxz1dd|tarxz2dd|tarxz3dd|tarxz4dd|tarxz5dd|tarxz6dd|tarxz7dd|tarxz8dd|tarxz9dd|tarxz10dd|tarxz11dd) (set -x; tar -J -f ${tapeDrive} ${tarReadOptions} -t > "${tapeContentFile}");;
		*) echo -e "\n!!! WRONG MODE !!!"; $0; exit -1 ;;
	esac
	echo
	( set -x; wc -l "${tapeContentFile}" )
	echo
	date
	echo

	# compress content file
	(set -x; bzip2 -9 "${tapeContentFile}"; ls -lh "${tapeContentFile}.bz2" )

	# write list of the files from the last tape
	echo
	echo "write the list of the content to the tape drive"
	( set -x; mt -f ${tapeDrive} rewind )
	( set -x; mt -f ${tapeDrive} fsf 1 )
	( set -x; mt -f ${tapeDrive} status | grep 'file number =' )
	echo
	date
	echo
	( set -x; tar ${tarCreateOptions} -f ${tapeDrive} --multi-volume "${tapeContentFile}.bz2" )
	echo 
	( set -x; mt -f ${tapeDrive} status | grep 'file number =' )
	echo

	echo "rewind ${tapeDrive}"
	( set -x; mt -f ${tapeDrive} rewind )
	( set -x; mt -f ${tapeDrive} status | grep 'file number =' )
	echo
	date
	echo
fi

echo "some information about the tape in ${tapeDrive}"
sg_read_attr ${tapeDrive} | grep 'Medium serial number\|MiB'
echo
if [ "${createCheckSumFile}" = "y" ]; then (set -x; bzip2 -9 ${md5ChecksumFile}); echo; fi

echo "The backup could be finished now. Please check the files on '${logFolder}' later."
echo
if [ "${ejectTapeAtWriteEnd}" = 'y' ]
then
	(set -x; mt -f ${tapeDrive} eject)
	echo
fi
date
echo

echo "To restore the full backup you can try the folowing command:"
echo -n "mt -f /dev/nst0 rewind; "
case "${mode}" in
	tar) echo "tar -f ${tapeDrive} ${tarReadOptions} -x";;
	targz1|targz2|targz3|targz4|targz5|targz6|targz7|targz8|targz9) echo "dd if=${tapeDrive} bs=${ddBlockSize} | pigz -d | tar ${tarReadOptions} -x";;
	tarxz1dd|tarxz2dd|tarxz3dd|tarxz4dd|tarxz5dd|tarxz6dd|tarxz7dd|tarxz8dd|tarxz9dd|tarxz10dd|tarxz11dd) echo "tar -J -f ${tapeDrive} ${tarReadOptions} -x";;
esac
echo

echo "end of: $0 $mode $@"
echo
cat "${logFile}" | mail -s "tape BACKUP FINISHED" ${mailSendTo}

exit 0
