#!/bin/bash
#
# a simple script for CRON to check if the tape drive is waiting for a new tape
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

folderOfLogFiles='/root/tape_backups/'
email="example@domain.tld"
tapeIsBusy=`lsof /dev/nst0`

cd $folderOfLogFiles || exit -1
lastTextFile=$folderOfLogFiles`ls -1t | head -n 1`
lastLineOfTextFile=`tail -n 1 "$lastTextFile"`
grepResult=`echo $lastLineOfTextFile | grep 'Prepare volume #\|Insert tape 1 and press return'`

if [ -z "$tapeIsBusy" ] && [ -n "$grepResult" ]
then
	echo "$grepResult" | mail -s "Please change tape on the server `hostname` to continue." $email
fi

exit 0