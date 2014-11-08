rsync-backup
============

Simple bash script that takes care of backing up your data 

#### True set & forget functionality
Runs from a cron job, and only bothers you if an error occurs. <br / >
Weekly emails inform you the cron job is still present and functional.

#### Backup to and from remote hosts as well as local disks
Only tranfer and store data that has changed.
Save bandwidth and disk space.

#### Keep an archive of data up to one year back
Reliable and persistent
Continues to retry transfering the files until succesful, or a user set max retry limit.

#### Use soft links to identify the most recent succesful backup
Incomplete backups will not be used for the next incremental backup.

#### Easy navigation & recovery of backed up data
Use familiar file management tools, including cd and ls, to peruse and restore archived data.

#### Advanced locking
Only one instance of the backup will run at any given time. A long (remote) backup will never be overun by the cron job from the next day. Stale lock files will be removed automatically.

#### Versatile & compatible
Remote machines can run bash and csh as their native login shells (and possibly others).
