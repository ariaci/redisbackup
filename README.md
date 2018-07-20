# redisbackup
Script to make automatic backups of all your Redis databases based on mysqlbackup v3.7 script written by Kenneth Fribert (https://forum.qnap.com/viewtopic.php?t=15628).

# FEATURES
* Every day the backup will be tar'ed and compressed to a file, tar archive is placed depending on the week and month day.
* Backups are put in a daily, weekly or monthly archive
* Old backups will be removed when they are X days old (you can of course change how many backups you want to keep by changing the value in the configfile, you can adjust both how many daily, weekly and monthly you wish to keep, defaults are 6,5,3).
* You choose which day you want to keep the weekly backup (default is 1 = monday)
* When you run the script you should see a bit information on what it's doing.
* The System log will reflect the script status.
* Backups can be placed in a subfolder under the share, use the parameter folder in the config.

# Requirements
* A share set up in QNAP's admin interface (setable in the config)
* It is possible to have the backup placed under a folder under the share, use the folder= parameter in the config
* A directory under the above share/folder called redis (it will be created automatically if it does not exist) this is used for temporary storage of databases.
* Directories under the above share/folder called redis.daily, redis.weekly and redis.monthly (they will be created automatically if they do not exist)
* The redis-cli command
Loglevel
It appears that not all are on page with the log function, the levels are:
0 Nothing is logged
1 Errors are logged
2 Warnings are logged
3 Informationals are logged
Only messages with priority of this or higher is sent to the system log.

# Default searchfolders for redis-cli?
The path used to search for redis-cli can be overriden by configfile. You can list multiple search folders separated by space. If unconfigured in config the script will use the 
default library/redis:latest-image (available at Docker-Hub) folder for redis-cli: /usr/local/bin

# The redisbackup server and port
You can override the server and port in configfile. If server is left unconfigured the script will use 127.0.0.1 as default. As default port the script will use 6379.

# The redisbackup password for the script (if needed)
The script can use a password for accessing the Redis databases. The password for the script can be set in the configfile.

# Location of configuration file
The config file is to be placed here: /etc/config/redisbackup.conf
Alternatively, the configuration file to be used can also be passed to the script as the first parameter.
