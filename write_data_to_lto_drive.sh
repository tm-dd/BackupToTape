#!/bin/bash
#
# a basic script to write data to a tape drive
#
# Copyright (c) 2024 tm-dd (Thomas Mueller)
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

tapeDrive=/dev/nst0
tarBlockingFactorOptionalOption='--blocking-factor=2048'
tarCreateOptions="-c ${tarBlockingFactorOptionalOption}"
tarReadOptions=-"t -v ${tarBlockingFactorOptionalOption}"
# tarCompressProgramAndOptions='pigz -3 -r'
tarCompressProgramAndOptions=''

pipeTarToDd='n'
ejectTapeAtWriteEnd='y'
mailSendTo='root'
createCheckSumFile='y'

timeFileNamesOffset=`date +"%Y-%m-%d_%H-%M"`
logfile="/root/tape_backups/${timeFileNamesOffset}_tape_backup_notes.txt"
tapeContentList="/root/tape_backups/${timeFileNamesOffset}_tape_backup_content.txt"
md5ChecksumFile="/root/tape_backups/${timeFileNamesOffset}_tape_backup_checksums.md5"

# write all stdout and stderr also into a file
exec > >(tee "${logfile}") 2>&1

if [ -z "${1}" ]
then
	echo
	echo "try to write some data to ${tapeDrive}"
	echo "USAGE: $0 tobackup1 [tobackup2] [...]"
	echo
	exit -1
fi

echo
echo "start of: $0 $@"
echo
date
echo
(set -x; pwd)
echo

if [ -z "`which sg_read_attr`" ]
then 
	echo "install software to read the serial number"
	( set -x; apt install sg3-utils )
	echo
fi

echo "tape on ${tapeDrive}"
sg_read_attr ${tapeDrive} | grep 'Medium serial number\|MiB' || exit -1
echo

echo "rewind ${tapeDrive}"
( set -x; mt -f ${tapeDrive} rewind )
( set -x; mt -f ${tapeDrive} status )
echo

numOfFiles='?'

echo "checking the size of the backup data"
fullSizeInGigaByte=0; 
for lineInGigaByte in `du -s -BG $@ 2> /dev/null | awk '{ print $1 }' | sed 's/G$//'`
do
	let fullSizeInGigaByte=${fullSizeInGigaByte}+${lineInGigaByte}
done
echo
date
echo

if [ "${createCheckSumFile}" = 'y' ]
then
	rm -f "${md5ChecksumFile}"
	echo "create checksum file '${md5ChecksumFile}' for a later file integrity check for the files (in total about ${fullSizeInGigaByte} GB) on the tape"
	echo "create CHECKSUM file '${md5ChecksumFile}' for a later file integrity check for the files (in total about ${fullSizeInGigaByte} GB) on the tape" | mail -s 'start creating checksum file for data for the tape' ${mailSendTo}
	if [ -n "`which parallel`" ]
	then
		find $@ -type f | parallel -j 16 md5sum > "${md5ChecksumFile}"
	else
		echo "missing software 'parallel'";
		find $@ -type f -exec md5sum {} + > "${md5ChecksumFile}"
	fi
	numOfFiles=`wc -l "${md5ChecksumFile}" | awk '{ print $1 }'`
	echo
	date
	echo
fi

if [ "${tarCompressProgramAndOptions}" != "" ]
then
	echo "write the COMPRESSED content of ${fullSizeInGigaByte} UNCOMPRESSED gigabytes (and some more) with ${numOfFiles} files to the tape drive"
	echo "write the COMPRESSED content of ${fullSizeInGigaByte} UNCOMPRESSED gigabytes (and some more) with ${numOfFiles} files to the tape drive" | mail -s "start writing tape" ${mailSendTo}
	echo
	if [ "$pipeTarToDd" = 'y' ]
	then
		echo "using the following command line to write: tar --use-compress-program="${tarCompressProgramAndOptions}" ${tarCreateOptions} ${md5ChecksumFile} $@ | dd of=${tapeDrive} bs=1M"
		( echo; set -x; time tar --use-compress-program="${tarCompressProgramAndOptions}" ${tarCreateOptions} ${md5ChecksumFile} $@ | dd of=${tapeDrive} bs=1M )
	else
		echo "using the following command line to write: tar --use-compress-program="${tarCompressProgramAndOptions}" ${tarCreateOptions} -f ${tapeDrive} ${md5ChecksumFile} $@"
		( echo; set -x; time tar --use-compress-program="${tarCompressProgramAndOptions}" ${tarCreateOptions} -f ${tapeDrive} ${md5ChecksumFile} $@ )
	fi
else
	echo "write the UNCOMPRESSED content of ${fullSizeInGigaByte} gigabytes (and some more) with ${numOfFiles} files to the tape drive"
	echo "write the UNCOMPRESSED content of ${fullSizeInGigaByte} gigabytes (and some more) with ${numOfFiles} files to the tape drive" | mail -s "start writing tape" ${mailSendTo}
	echo
	if [ "$pipeTarToDd" = 'y' ]
	then
		echo "using the following command line to write: tar ${tarCreateOptions} ${md5ChecksumFile} $@ | dd of=${tapeDrive} bs=1M"
		( echo; set -x; time tar ${tarCreateOptions} ${md5ChecksumFile} $@ | dd of=${tapeDrive} bs=1M )
	else
		echo "using the following command line to write: tar --multi-volume ${tarCreateOptions} -f ${tapeDrive} ${md5ChecksumFile} $@"
		( echo; set -x; time tar --multi-volume ${tarCreateOptions} -f ${tapeDrive} ${md5ChecksumFile} $@ )
	fi
fi
echo

( set -x; mt -f ${tapeDrive} status | grep 'file number =' )

echo
date
echo
echo "read backup and write the list of content to the file '${tapeContentList}'"
echo "read backup and write the list of content to the file '${tapeContentList}'" | mail -s "start reading tape" ${mailSendTo}
echo
( set -x; mt -f ${tapeDrive} rewind )
( set -x; mt -f ${tapeDrive} status | grep 'file number =' )
echo

if [ "$pipeTarToDd" = 'y' ]
then
	if [ "${tarCompressProgramAndOptions}" != "" ]
	then
		echo "using the following command line to read: dd if=${tapeDrive} bs=1M | pigz -d | tar ${tarReadOptions} > "'"'${tapeContentList}'"'
		( echo; set -x; time dd if=${tapeDrive} bs=1M | pigz -d | tar ${tarReadOptions} > "${tapeContentList}"; wc -l "${tapeContentList}" )
	else
		echo "using the following command line to read: dd if=${tapeDrive} bs=1M | tar ${tarReadOptions} > "'"'${tapeContentList}'"'
		( echo; set -x; time dd if=${tapeDrive} bs=1M | tar ${tarReadOptions} > "${tapeContentList}"; wc -l "${tapeContentList}" )
	fi
else
	if [ "${tarCompressProgramAndOptions}" != "" ]
	then
		echo "using the following command line to read: dd if=${tapeDrive} bs=1M | pigz -d | tar ${tarReadOptions} >  "'"'${tapeContentList}'"'
		( echo; set -x; time dd if=${tapeDrive} bs=1M | pigz -d | tar ${tarReadOptions} > "${tapeContentList}"; wc -l "${tapeContentList}" )
	else
		echo "using the following command line to read: tar ${tarReadOptions} -f ${tapeDrive} > "${tapeContentList}
		( echo; set -x; time tar ${tarReadOptions} -f ${tapeDrive} > "${tapeContentList}"; wc -l "${tapeContentList}" )
	fi
fi

echo
date
echo
echo "write the list of the content to the tape drive"
( set -x; mt -f ${tapeDrive} rewind )
( set -x; mt -f ${tapeDrive} fsf 1 )
( set -x; mt -f ${tapeDrive} status | grep 'file number =' )
echo
date
echo
if [ "$pipeTarToDd" = 'y' ]
then
	echo 'using the following command line to write: tar '${tarCreateOptions}' "'${tapeContentList}'" | dd of='${tapeDrive}' bs=1M'
	( echo; set -x; tar ${tarCreateOptions} "${tapeContentList}" | dd of=${tapeDrive} bs=1M )
else
	echo 'using the following command line to write: tar '${tarCreateOptions}' -f '${tapeDrive}' "'${tapeContentList}'"'
	( echo; set -x; tar ${tarCreateOptions} -f ${tapeDrive} "${tapeContentList}" )
fi
echo 

( set -x; mt -f ${tapeDrive} status | grep 'file number =' )
echo

echo "rewind ${tapeDrive}"
( set -x; mt -f ${tapeDrive} rewind )
( set -x; mt -f ${tapeDrive} status | grep 'file number =' )
echo

echo "tape on ${tapeDrive}"
sg_read_attr ${tapeDrive} | grep 'Medium serial number\|MiB'
echo

date
echo
(set -x; bzip2 -9 ${tapeContentList} ${md5ChecksumFile})
echo
date
echo
echo "The backup could be finished now. Please read '${tapeContentList}.bz2'  and '${md5ChecksumFile}.bz2' for the content and the checksums of the backup on the tape and check the file '${logfile}'."
echo
if [ "${ejectTapeAtWriteEnd}" = 'y' ]
then
	(set -x; mt -f ${tapeDrive} eject)
	echo
fi
date
echo
echo "end of: $0 $@"
echo
cat "${logfile}" | mail -s "tape backup finished" ${mailSendTo}

exit 0
