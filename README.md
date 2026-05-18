# write data to a LTO drive 

## ABOUT ##

The script write_data_to_lto_drive.sh allow to write folders and files to a local connected LTO drive on linux.
The script write_zfs_snapshot_to_lto_drive_with_mbuffer.sh do the same like write_data_to_lto_drive.sh, but mostly much faster and read the tape after writing directly, to make the full process faster.
The script write_zfs_snapshot_to_lto_drive_with_mbuffer_and_checksum.sh allows to write a ZFS Snapshot or a differential ZFS Snapshot and read the tapes directly to check the full backup.

## Explaining with two examples

Example: write_data_to_lto_drive.sh /data/folder1 /home/folder2 /etc/file

* calculate the size of the content
* create MD5 checksums of all files in the content
* write the content and the MD5 checksums to the tape 
* read the tape
* write a text file with the content of the tape on the second place on the tape

Example: write_zfs_snapshot_to_lto_drive_with_mbuffer_and_checksum.sh zfspool@data1@today

* print some information about the tape
* print the size of the ZFS snapshot
* write the first tape of the ZFS snapshot and start creating of the checksum of the full backup
* read the first tape of the ZFS snapshot to create the checksum of the full backup
* if the tape was ended, send a mail to the user to change the tape and write and read the next tape(s)
* at the end of all tapes, print the checksums of the data to write and the date after reading the tape(s)
* it create a list of files from the ZFS snapshot
* send a mail with the important notes of the backup process to the user
* at last give some information for the user, like notes for restoring the ZFS snapshot and files from the process

All steps and the used commands will write to a text file for the user.

Thomas Mueller <><
