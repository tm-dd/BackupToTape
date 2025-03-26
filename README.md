# write data to a LTO drive 

## ABOUT ##

The script write_data_to_lto_drive.sh allow to write folders and files to a local connected LTO drive on linux.

## Explaining with an example

Example: write_data_to_lto_drive.sh /data/folder1 /home/folder2 /etc/file

This can do the following with the content of this folders and the file:

* calculate the size of the content
* create MD5 checksums of all files in the content
* write the content and the MD5 checksums to the tape 
* read the tape
* write a text file with the content of the tape on the second place on the tape

All steps and the used commands will write to a text file for the user.

Thomas Mueller <><
# BackupToTape
