#!/bin/bash

first_test=1
last_test=35
script=run_test.sh
log_file=test.log

# Call init to set up testing environment
bash ./_test/"$script" init

for i in $(seq $first_test $last_test); do
    bash ./_test/"$script" $i 2>> $log_file
done | tee results.txt

cat results.txt | grep '\[.*\]$' | awk -F '[] /[]+' '
BEGIN {
    sum=0
}

{
	sum += $(NF-2);
}

END {
    printf "\n%66s  [%02d/90]\n", "Total:", sum;
}'

# Cleanup testing environment
bash ./_test/"$script" cleanup
rm -f results.txt
