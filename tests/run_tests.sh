RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
NORMAL="\033[0m"

fail_count=0
pass_count=0

for testCase in tc*; do
	cd $testCase;
	./run.sh;
	if [ $? -eq 0 ]; then
		echo -e "${YELLOW}$testCase:${NORMAL} ... ${GREEN}Pass${NORMAL}";
		let pass_count=pass_count+1
	else
		echo -e "${YELLOW}$testCase:${NORMAL} ... ${RED}Fail${NORMAL}";
		let fail_count=fail_count+1
	fi
	cd - > /dev/null;
done

if [ $fail_count -eq 0 ]; then
	echo -e "${GREEN}${pass_count} tests passed and ${fail_count} failed.${NORMAL}"
else
	echo -e "${RED}${pass_count} tests passed and ${fail_count} failed.${NORMAL}"
	exit 1
fi
