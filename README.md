# GRUC-script
Jack's GRUC (Git Repo Update Checker) script. It checks for new commits in any git repos found in any subdirectories (including following symlinks) of the folder the script is in.
If any have new commits, it notifies the user via a desktop notification and includes the names of the folders with the repos, and # of commits behind it is.

Setup:
Place this script into a folder that is the parent of subfolders containing git repos. 
For auto-upgrade functionality, also create a script (or symlink to the repo's included install script if it exists), making sure it shares a name with the folder in which the git repo it will run for is. Example: For a local clone living in rootfolder/foo/bar, create a script in rootfolder/foo (or place a symlink to the repo's install script in rootfolder/foo/bar) named bar.sh.

Program arguments:
--update: Also fast forward local clones to be up to date with remote.
--upgrade: Also run the install scripts for all local clones.
