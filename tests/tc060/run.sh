set -e
set -u

../../bin/dcd-client $1 --full file.d -c7 > actual1.txt

minimumsize=100 # identifiers + the symbols without documentation + some margin
actualsize=$(wc -c < "actual1.txt")

# we don't want to unittest the documentation, so we just check if there is something that makes it longer than it would be

if [ $actualsize -ge $minimumsize ]; then
	exit 0
else
	cat actual1.txt
	exit 1
fi
