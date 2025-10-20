#!/bin/bash

# Jack's GRUC (Git Repo Update Checker) script. It checks for new commits in any git repos found in any subdirectories including following symlinks of the folder the script is in.
# If any have new commits, it notifies the user via a desktop notification and includes the names of the folders with the repos, and # of commits behind it is. Can also be passed an argument to automatically update the local clone.
# Can also be passed an argument to run an existing installer script in the local clone.

# TODO: This could likely be done in a much, much less stupid way (especially the parsing of the output from git, which is a giant set of hacky workarounds). I *am* stupid though, so I can't fix it myself: Too bad!

set -o pipefail # if any command in a pipeline fails, not just specifically the last command in a pipe, then exit with an error. why is this not the default.

# force cleanup all temporary data that is used later now, to prevent any issues caused by garbage in from the system running the command (env vars used here already being set/used maliciously or unintentionally in the shell running the command, temp files that are maliciously crafted or temp files from previous executions that were left uncleaned when the script runs, etc.)
scriptpath=''
newcommits=''
pullupdates=''
recompile=''
TEMPDEBUG=''
rm --preserve-root=all --one-file-system ./tempfileneedsupdate ./tempfilestatus ./tempfileallscripts

# sanity checking that all commands used by the script actually exist
for singlecmd in git find notify-send realpath dirname pwd grep; do # check that the commands that the script uses actually exist, before doing anything.
    if [ ! -z $(command -v "$singlecmd") ]; then
        : # this is the shell equivalent to NOOP, aka do nothing.
    else
        echo "Command $singlecmd was not found, aborting execution!"
        exit 1
    fi
done

# sanity checking execution location and PWD, also finds and changes the PWD to where the script actually lives on disk.
scriptpath=$(dirname $(realpath "$0")) # store the absolute path to the script in an env var
if [ $PWD != $scriptpath -o $(pwd) != $scriptpath ]; then # if the folder the script is in is NOT the PWD (or the PWD fails to be found), then throw an error. I discourage running the script in a PWD that isn't where it lives, since it writes and deletes arbitrary files at where it lives.
	echo "Error: This script is being run in a PWD other than where the script lives (**PLEASE DO NOT DO THIS!**), '$PWD' is not in the PATH, or dirname or realpath somehow cannot find the script's location."
	echo "In any of these cases, it is preferable to throw a fatal error than to run in a potentially/likely broken environment. Exiting!"
	exit 1
fi
cd $scriptpath

# argument parsing; a lazy implementation of it.
if [ ! $# -eq 0 ]; then
	for arg in "$@"
	do
		if [ $arg = "--pull" -o $arg = "-P" ]; then
			pullupdates=true
			# echo "Also fast-forwarding repos to be up to date with remote!"
		elif [ $arg = "--update" -o $arg = "-U" ]; then
			recompile=true
			# echo "Also running any install scripts found in repos!"
		fi
	done
fi


if [ -z $TEMPDEBUG ]; then # debug feature, so that I don't spam github/gitlab/etc while testing parts of the script that don't need to interact with the git repos or the git CLI to work.

	# find git repos, and for each one: update references to remote, parse the output of git status to see if the local clone is behind remote, and output to a temp file if it is.
	for i in `find -L . -maxdepth 5 -type d -name ".git"`; do # for each .git directory found residing in any level of subdirectory including following symlinks below the folder the script lives in...
		cd $i/.. # changes directory to the parent of the .git directory found by find (which puts the current directory as being the root of the local clone)
		git remote update > /dev/null # update references to remote, do not output to console
		git status -uno > $scriptpath/tempfilestatus # print status of local clone compared to the (now checked for updates) remote repo, write output to a temp file.

		# parse git status output for if the repo is outdated, and if it is parse out the path to the repo and how many commits behind it is. After, if specified by user, fast-forward the clone to be up to date with remote.
		if [ $(grep -c "Your branch is behind" $scriptpath/tempfilestatus) -eq 1 ]; then # if the local branch is behind on commits, then..
			newcommits=$(grep -P -o -e "(?<=Your branch is behind \'[a-z0-9\/]{1,20}\' by )(\d{1,4})" $scriptpath/tempfilestatus) # ..grep for the number of commits behind the clone is, store the result in a var
			echo $i > $scriptpath/tempfilerepopath # have to write the repo's full path to a secpmd temp file to make grep work nicely with it. TODO: I hate this, its a really annoying forced hacky workaround. Too bad!
			echo "$(grep -P -o -e "(?<=\.\/).*(?=\/\.git)" $scriptpath/tempfilerepopath) is behind by $newcommits commits" >> $scriptpath/tempfileneedsupdate # grep the temp file containing the path found by the find command, using a regex to convert it into the path to the root folder of the git clone. then, append that in a human readable message that also includes the number of commits behind the clone is, into a third temp file.
		fi

		# if the user specified to update the local clone, then do it here
		if [ $pullupdates -a $pullupdates = "true" ]; then
			# echo "fast-forwarding "$i" to be up to date with remote" # debug
			git pull
		fi

		# if the user specified to run install scripts, and this repo was behind, and...
		if [ $(grep -c "Your branch is behind" $scriptpath/tempfilestatus) -eq 1 -a $recompile = "true" ]; then
			currentdirname=${PWD##*/} # get the name of the current directory (direct credit to https://stackoverflow.com/questions/1371261/get-current-directory-or-folder-name-without-the-full-path)
			if [ -e $(echo ${PWD}/../${currentdirname}.sh) ]; then # if the install script for GRUC was created, then...
				echo 'cd' $PWD '&&' $PWD/../${currentdirname}.sh >> $scriptpath/tempfileallscripts # append a oneliner that changes to the repo directory and then runs the install script, into a temp file
			fi
		fi
		cd $scriptpath # return to the script's directory before the next loop, since find outputs directories as the path relative to where it was ran
	done

	if [ -s $scriptpath/tempfileallscripts ]; then # if the previous for loop found repos ready to be updated, then...
		chmod +x $scriptpath/tempfileallscripts # since the temp file should be all valid bash script, make the temp file executable, and...
		pkexec --keep-cwd bash -c $scriptpath/tempfileallscripts # graphically prompt the user via pkexec to run all of those scripts as root. I was not expecting to pull a jank but super elegant solution to "how do I run all of these fucking scripts without asking for auth for all of them? (there may be a large amount of them)" out of my ass but here we are.
	fi


	if [ -s $scriptpath/tempfileneedsupdate ]; then # if the previous for loop found any repos with new commits, and...
		if [ $pullupdates = '' ]; then # updates are not to be pulled, then...
			notify-send -a "Jack's GRUC script" 'Local repositories have new commits!' "$(cat ./tempfileneedsupdate)" # ..notify of any repos found to be outdated. includes path relative to script, and num of commits behind.
		elif [ $pullupdates = "true" ]; then
			notify-send -a "Jack's GRUC script" 'Local repositories were fast-forwarded!' "$(cat ./tempfileneedsupdate)" # notify that repos were updated, with the same info as above.
		elif [ $recompile = "true" ]; then
			notify-send -a "Jack's GRUC script" 'Local repositories were fast-forwarded and programs recompiled!' "$(cat ./tempfileneedsupdate)" # notify that repos were updated and install scripts reran, with the same info as above.
		fi
	fi

	rm --preserve-root=all --one-file-system ./tempfileneedsupdate ./tempfilestatus ./tempfilerepopath ./tempfileallscripts # temp file cleanup
fi

# cleaning up vars
scriptpath=''
newcommits=''
pullupdates=''
recompile=''
currentdir=''
