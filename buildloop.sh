while $(true);
do
	clear
	tput bold; tput setaf 3; date; tput sgr0
	make debug -j > /dev/null
	if [[ $? -eq 0 ]]; then
		tput bold; tput setaf 2; echo "Build succes"; tput sgr0
	else
		tput bold; tput setaf 1; echo "Build failure"; tput sgr0
	fi

	inotifywait src makefile libdparse dsymbol -r -e modify -q;
done
