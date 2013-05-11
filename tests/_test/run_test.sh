#!/bin/bash

#
# Testing framework - bash version
#
# 2012, Operating Systems
#

# ----------------- General declarations and util functions ------------------ #

exec_name="./aws"
exec_pid="-1"
aws_listen_port=8888
static_folder="./static/"
dynamic_folder="./dynamic/"

DEBUG_=1

LOG_FILE=test.log
WGET_LOG=wget.log
DO_CLEANUP=yes

# Enable/disable exiting when program fails.
EXIT_IF_FAIL=0

max_points=90

DEBUG()
{
	if test "x$DEBUG_" = "x1"; then
		$@ 1>&2
	fi
}

print_header()
{
	header="${1}"
	header_len=${#header}
	printf "\n"
	if [ $header_len -lt 71 ]; then
		padding=$(((71 - $header_len) / 2))
		for ((i = 0; i < $padding; i++)); do
			printf " "
		done
	fi
	printf "= %s =\n\n" "${header}"
}

test_do_fail()
{
	points=$1
	printf "failed  [ 0/%02d]\n" "$max_points"
	if test "x$EXIT_IF_FAIL" = "x1"; then
		exit 1
	fi
}

test_do_pass()
{
	points=$1
	printf "passed  [%02d/%02d]\n" "$points" "$max_points"
}

basic_test()
{
	printf "%02d) %s" "$test_index" "$description"

	for ((i = 0; i < 56 - ${#description}; i++)); do
		printf "."
	done

	$@ > /dev/null 2>&1
	if test $? -eq 0; then
		test_do_pass "$points"
	else
		test_do_fail "$points"
	fi
}

# ---------------------------------------------------------------------------- #

# ----------------- Init and cleanup tests ----------------------------------- #

# Initializes a test
init_test()
{
	$exec_name &>> $LOG_FILE &
	if test $? -eq 0; then
		exec_pid=$!
	fi
	sleep 1
}

# Cleanups a test
cleanup_test()
{
	kill -9 "$exec_pid" &>> $LOG_FILE
	if [ "$DO_CLEANUP" = "yes" ]; then
		rm -rf $WGET_LOG &>> $LOG_FILE
	fi
}

# Initializes the whole testing environment
# Should be the first test called
init_world()
{
	[ -d $static_folder ] && rm -rf $static_folder &>> $LOG_FILE
	[ -d $dynamic_folder ] && rm -rf $dynamic_folder &>> $LOG_FILE
	mkdir $static_folder &>> $LOG_FILE
	mkdir $dynamic_folder &>> $LOG_FILE

	print_header "Testing - Web Server"

	for i in $(seq -f "%02g" 0 49); do
		dd if=/dev/urandom of=$static_folder/small$i.dat bs=2K count=1 &>> $LOG_FILE
		dd if=/dev/urandom of=$static_folder/large$i.dat bs=1M count=1 &> $LOG_FILE
		ln -sf ../$static_folder/small$i.dat $dynamic_folder/small$i.dat
		ln -sf ../$static_folder/large$i.dat $dynamic_folder/large$i.dat
	done
}

# Cleanups the whole testing environment
# Should be the last test called
cleanup_world()
{
	if [ "$DO_CLEANUP" = "yes" ]; then
		rm -fr $static_folder &>> $LOG_FILE
		rm -fr $dynamic_folder &>> $LOG_FILE
		rm -fr $LOG_FILE
	fi
}

# ---------------------------------------------------------------------------- #

# ----------------- Test Suite ----------------------------------------------- #


test_executable_exists()
{
    init_test

    basic_test test -e "$exec_name"

    cleanup_test
}

test_executable_runs()
{
    init_test

    basic_test ps -C aws

    cleanup_test
}

# Use lsof to see whether server is listening on proper port.
test_is_listening()
{
    init_test

    lsof -p "$exec_pid" | awk -F '[ \t]+' '{print $8, $10;}' | grep TCP | \
		grep LISTEN > /dev/null 2>&1
    basic_test test "$?" -eq 0

    cleanup_test
}

test_is_listening_on_port()
{
    init_test

    lsof -p "$exec_pid" | awk -F '[ \t]+' '{print $9;}' | \
		grep "$aws_listen_port" > /dev/null 2>&1
    basic_test test "$?" -eq 0

    cleanup_test
}

# Use netcat for connecting to server.
test_accepts_connections()
{
    init_test

    nc -d localhost "$aws_listen_port" &
    nc_pid=$!
    sleep 1
    lsof -p "$exec_pid" | awk -F '[ \t]+' '{print $8, $10;}' | grep TCP | \
		grep ESTABLISHED > /dev/null 2>&1
    basic_test test $? -eq 0

    kill -9 "$nc_pid" > /dev/null 2>&1

    cleanup_test
}

test_accepts_multiple_connections()
{
    init_test

    nc -d localhost "$aws_listen_port" &
    nc_pid1=$!
    nc -d localhost "$aws_listen_port" &
    nc_pid2=$!
    sleep 1
    n_conns=$(lsof -p "$exec_pid" | awk -F '[ \t]+' '{print $8, $10;}' | \
		grep TCP | grep ESTABLISHED | wc -l 2> /dev/null)
    DEBUG echo "n_conns: $n_conns"

    basic_test test $n_conns -eq 2

    kill -9 "$nc_pid1" "$nc_pid2" > /dev/null 2>&1

    cleanup_test
}

# Use nm to list undefined symbols in executable file.
test_uses_epoll()
{
    init_test

    nm -u "$exec_name" | grep epoll > /dev/null 2>&1
    basic_test test $? -eq 0

    cleanup_test
}

test_disconnect()
{
    init_test

    nc -d localhost "$aws_listen_port" &
    nc_pid=$!
    kill -9 "$nc_pid" > /dev/null 2>&1
    lsof -p "$exec_pid" | awk -F '[ \t]+' '{print $8, $10;}' | grep TCP | \
		grep ESTABLISHED > /dev/null 2>&1
    basic_test test $? -ne 0

    cleanup_test
}

test_multiple_disconnect()
{
    init_test

    nc -d localhost "$aws_listen_port" &
    nc_pid1=$!
    nc -d localhost "$aws_listen_port" &
    nc_pid2=$!
    kill -9 "$nc_pid1" "$nc_pid2" > /dev/null 2>&1
    lsof -p "$exec_pid" | awk -F '[ \t]+' '{print $8, $10;}' | grep TCP | \
		grep ESTABLISHED > /dev/null 2>&1

    basic_test test $? -ne 0

    cleanup_test
}

test_connect_disconnect_connect()
{
    init_test

    nc -d localhost "$aws_listen_port" &
    nc_pid=$!
    kill -9 "$nc_pid" > /dev/null 2>&1
    nc -d localhost "$aws_listen_port" &
    nc_pid=$!
    lsof -p "$exec_pid" | awk -F '[ \t]+' '{print $8, $10;}' | grep TCP | \
		grep ESTABLISHED > /dev/null 2>&1
    basic_test test $? -eq 0

    kill -9 "$nc_pid" > /dev/null 2>&1

    cleanup_test
}

test_multiple_c_d_c()
{
    init_test

    nc -d localhost "$aws_listen_port" &
    nc_pid1=$!
    kill -9 "$nc_pid1" > /dev/null 2>&1
    nc -d localhost "$aws_listen_port" &
    nc_pid1=$!
    nc -d localhost "$aws_listen_port" &
    nc_pid2=$!
    kill -9 "$nc_pid2" > /dev/null 2>&1
    nc -d localhost "$aws_listen_port" &
    nc_pid2=$!

    n_conns=$(lsof -p "$exec_pid" | awk -F '[ \t]+' '{print $8, $10;}' | \
		grep TCP | grep ESTABLISHED | wc -l 2> /dev/null)
    basic_test test "$n_conns" -eq 2

    kill -9 "$nc_pid1" "$nc_pid2" > /dev/null 2>&1
    cleanup_test
}

test_unordered_c_d_c()
{
    init_test

    nc -d localhost "$aws_listen_port" &
    nc_pid1=$!
    nc -d localhost "$aws_listen_port" &
    nc_pid2=$!
    kill -9 "$nc_pid1" "$nc_pid2" > /dev/null 2>&1
    nc -d localhost "$aws_listen_port" &
    nc_pid1=$!
    nc -d localhost "$aws_listen_port" &
    nc_pid2=$!
    n_conns=$(lsof -p "$exec_pid" | awk -F '[ \t]+' '{print $8, $10;}' | \
		grep TCP | grep ESTABLISHED | wc -l 2> /dev/null)
    basic_test test "$n_conns" -eq 2

    kill -9 "$nc_pid1" "$nc_pid2" > /dev/null 2>&1
    cleanup_test
}

test_replies_http_request()
{
    init_test

    echo -e "GET /$(basename $static_folder)/small00.dat HTTP/1.0\n" | \
		nc -q 2 localhost $aws_listen_port > small00.dat 2> /dev/null
    head -1 small00.dat | grep '^HTTP/' > /dev/null 2>&1
    basic_test test $? -eq 0

    rm small00.dat
    cleanup_test
}

test_replies_http_request_1()
{
    init_test

    echo -e "GET /$(basename $static_folder)/small00.dat HTTP/1.1\n" | \
		nc -q 2 localhost $aws_listen_port > small00.dat 2> /dev/null
    head -1 small00.dat | grep '^HTTP/' > /dev/null 2>&1
    basic_test test $? -eq 0

    rm small00.dat
    cleanup_test
}

test_uses_sendfile()
{
    init_test

    nm -u "$exec_name" | grep sendfile > /dev/null 2>&1
    basic_test test $? -eq 0

    cleanup_test
}

test_get_small_file_wget()
{
    init_test

    wget "http://localhost:8888/$(basename $static_folder)/small00.dat" \
		-o $WGET_LOG -O small00.dat
    basic_test test $? -eq 0

    rm small00.dat
    cleanup_test
}

test_get_small_file_wget_cmp()
{
    init_test

    wget "http://localhost:8888/$(basename $static_folder)/small00.dat" \
		-o $WGET_LOG -O small00.dat
    cmp small00.dat $static_folder/small00.dat > /dev/null 2>&1
    basic_test test $? -eq 0

    rm small00.dat
    cleanup_test
}

test_get_large_file_wget()
{
    init_test

    wget "http://localhost:8888/$(basename $static_folder)/large00.dat"\
		-o $WGET_LOG -O large00.dat
    basic_test test $? -eq 0

    rm large00.dat
    cleanup_test
}

test_get_large_file_wget_cmp()
{
    init_test

    wget "http://localhost:8888/$(basename $static_folder)/large00.dat" \
		-o $WGET_LOG -O large00.dat
    cmp large00.dat $static_folder/large00.dat > /dev/null 2>&1
    basic_test test $? -eq 0

    rm large00.dat
    cleanup_test
}

test_get_bad_file_404()
{
    init_test

    echo -e "GET /$(basename $static_folder)/abcdef.dat HTTP/1.0\n" | \
		nc -q 2 localhost $aws_listen_port > abcdef.dat 2> /dev/null
    head -1 abcdef.dat | grep '^HTTP/' | grep '404' > /dev/null 2>&1
    basic_test test $? -eq 0

    rm abcdef.dat
    cleanup_test
}

# Use non-static and non-dynamic file path.
test_bad_path_404()
{
    init_test

    echo -e "GET /xyzt/abcdef.dat HTTP/1.0\n" | \
		nc -q 2 localhost $aws_listen_port > abcdef.dat 2> /dev/null
    head -1 abcdef.dat | grep '^HTTP/' | grep '404' > /dev/null 2>&1
    basic_test test $? -eq 0

    rm abcdef.dat
    cleanup_test
}

test_get_one_file_then_another()
{
    init_test

    wget "http://localhost:8888/$(basename $static_folder)/large00.dat" \
		-o /dev/null -O large00.dat
    wget "http://localhost:8888/$(basename $static_folder)/large01.dat" \
		-o /dev/null -O large01.dat
    cmp large00.dat $static_folder/large00.dat > /dev/null 2>&1
    code1=$?
    cmp large01.dat $static_folder/large01.dat > /dev/null 2>&1
    code2=$?
    basic_test test $code1 -eq 0 -a $code2 -eq 0

    rm large00.dat large01.dat
    cleanup_test
}

test_get_two_simultaneous_files()
{
    init_test

    wget "http://localhost:8888/$(basename $static_folder)/large00.dat" \
		-o /dev/null -O large00.dat &
    pid1=$!
    wget "http://localhost:8888/$(basename $static_folder)/large01.dat" \
		-o /dev/null -O large01.dat &
    pid2=$!
    wait $pid1
    wait $pid2
    cmp large00.dat $static_folder/large00.dat > /dev/null 2>&1
    code1=$?
    cmp large01.dat $static_folder/large01.dat > /dev/null 2>&1
    code2=$?
    basic_test test $code1 -eq 0 -a $code2 -eq 0

    cleanup_test
}

test_get_multiple_simultaneous_files()
{
    init_test

    ret_val=0
    declare -a pids
    for i in $(seq 0 49); do
        filename=large$(printf "%02g" $i).dat
        wget "http://localhost:8888/$(basename $static_folder)/$filename" \
			-o /dev/null -O $filename &
        pids[$i]=$!
    done
    for i in $(seq 0 49); do
        wait ${pids[$i]}
    done
    for i in $(seq 0 49); do
        filename=large$(printf "%02g" $i).dat
        if ! cmp $static_folder/$filename $filename > /dev/null 2>&1; then
            ret_val=1
            break
        fi
    done

    basic_test test $ret_val -eq 0

    for i in $(seq 0 49); do
        filename=large$(printf "%02g" $i).dat
        rm $filename
    done
    cleanup_test
}

test_uses_io_submit()
{
    init_test

    nm -u "$exec_name" | grep io_submit > /dev/null 2>&1
    basic_test test $? -eq 0

    cleanup_test
}

test_get_small_dyn_file_wget()
{
    init_test

    wget "http://localhost:8888/$(basename $dynamic_folder)/small00.dat" \
		-o $WGET_LOG -O small00.dat
    basic_test test $? -eq 0

    rm small00.dat
    cleanup_test
}

test_get_small_dyn_file_wget_cmp()
{
    init_test

    wget "http://localhost:8888/$(basename $dynamic_folder)/small00.dat" \
		-o $WGET_LOG -O small00.dat
    cmp small00.dat $dynamic_folder/small00.dat > /dev/null 2>&1
    basic_test test $? -eq 0

    rm small00.dat
    cleanup_test
}

test_get_large_dyn_file_wget()
{
    init_test

    wget "http://localhost:8888/$(basename $dynamic_folder)/large00.dat" \
		-o $WGET_LOG -O large00.dat
    basic_test test $? -eq 0

    rm large00.dat
    cleanup_test
}

test_get_large_dyn_file_wget_cmp()
{
    init_test

    wget "http://localhost:8888/$(basename $dynamic_folder)/large00.dat" \
		-o $WGET_LOG -O large00.dat
    cmp large00.dat $dynamic_folder/large00.dat > /dev/null 2>&1
    basic_test test $? -eq 0

    rm large00.dat
    cleanup_test
}

test_get_bad_dyn_file_404()
{
    init_test

    echo -e "GET /$(basename $dynamic_folder)/abcdef.dat HTTP/1.0\n" | \
		nc -q 2 localhost $aws_listen_port > abcdef.dat 2> /dev/null
    head -1 abcdef.dat | grep '^HTTP/' | grep '404' > /dev/null 2>&1
    basic_test test $? -eq 0

    rm abcdef.dat
    cleanup_test
}

test_get_one_dyn_file_then_another()
{
    init_test

    wget "http://localhost:8888/$(basename $dynamic_folder)/large00.dat" \
		-o /dev/null -O large00.dat
    wget "http://localhost:8888/$(basename $dynamic_folder)/large01.dat" \
		-o /dev/null -O large01.dat
    cmp large00.dat $dynamic_folder/large00.dat > /dev/null 2>&1
    code1=$?
    cmp large01.dat $dynamic_folder/large01.dat > /dev/null 2>&1
    code2=$?
    basic_test test $code1 -eq 0 -a $code2 -eq 0

    rm large00.dat large01.dat
    cleanup_test
}

test_get_two_simultaneous_dyn_files()
{
    # test sometimes fails, add sleep 1
    sleep 1

    init_test

    wget "http://localhost:8888/$(basename $dynamic_folder)/large00.dat" \
		-o /dev/null -O large00.dat &
    pid1=$!
    wget "http://localhost:8888/$(basename $dynamic_folder)/large01.dat" \
		-o /dev/null -O large01.dat &
    pid2=$!
    wait $pid1
    wait $pid2
    cmp large00.dat $dynamic_folder/large00.dat > /dev/null 2>&1
    code1=$?
    cmp large01.dat $dynamic_folder/large01.dat > /dev/null 2>&1
    code2=$?
    basic_test test $code1 -eq 0 -a $code2 -eq 0

    cleanup_test
}

test_get_mul_sim_dyn_files()
{
    init_test

    ret_val=0
    declare -a pids
    for i in $(seq 0 49); do
        filename=large$(printf "%02g" $i).dat
        wget "http://localhost:8888/$(basename $dynamic_folder)/$filename" \
			-o /dev/null -O $filename &
        pids[$i]=$!
    done
    for i in $(seq 0 49); do
        wait ${pids[$i]}
    done
    for i in $(seq 0 49); do
        filename=large$(printf "%02g" $i).dat
        if ! cmp $dynamic_folder/$filename $filename > /dev/null 2>&1; then
            ret_val=1
            break
        fi
    done

    basic_test test $ret_val -eq 0

    for i in $(seq 0 49); do
        filename=large$(printf "%02g" $i).dat
        rm $filename
    done
    cleanup_test
}

test_get_two_sim_stat_dyn_files()
{
    # test sometimes fails, add sleep 1
    sleep 1

    init_test

    wget "http://localhost:8888/$(basename $static_folder)/large00.dat" \
		-o /dev/null -O large00.dat &
    pid1=$!
    wget "http://localhost:8888/$(basename $dynamic_folder)/large01.dat" \
		-o /dev/null -O large01.dat &
    pid2=$!
    wait $pid1
    wait $pid2
    cmp large00.dat $static_folder/large00.dat > /dev/null 2>&1
    code1=$?
    cmp large01.dat $dynamic_folder/large01.dat > /dev/null 2>&1
    code2=$?
    basic_test test $code1 -eq 0 -a $code2 -eq 0

    cleanup_test
}

test_get_multiple_simultaneous_stat_dyn_files()
{
    init_test

    ret_val=0
    declare -a pids
    for i in $(seq 0 24); do
        filename=large$(printf "%02g" $i).dat
        wget "http://localhost:8888/$(basename $static_folder)/$filename" \
			-o /dev/null -O $filename &
        pids[$i]=$!
    done
    for i in $(seq 25 49); do
        filename=large$(printf "%02g" $i).dat
        wget "http://localhost:8888/$(basename $dynamic_folder)/$filename" \
			-o /dev/null -O $filename &
        pids[$i]=$!
    done
    for i in $(seq 0 49); do
        wait ${pids[$i]}
    done
    for i in $(seq 0 24); do
        filename=large$(printf "%02g" $i).dat
        if ! cmp $static_folder/$filename $filename > /dev/null 2>&1; then
            ret_val=1
            break
        fi
    done
    for i in $(seq 25 49); do
        filename=large$(printf "%02g" $i).dat
        if ! cmp $dynamic_folder/$filename $filename > /dev/null 2>&1; then
            ret_val=1
            break
        fi
    done

    basic_test test $ret_val -eq 0

    for i in $(seq 0 49); do
        filename=large$(printf "%02g" $i).dat
        rm $filename
    done
    cleanup_test
}


# specifies the tests, commands and points
test_fun_array=(								\
	test_executable_exists "Test executable exists" 1
	test_executable_runs "Test executable runs" 1
	test_is_listening "Test listening" 1
	test_is_listening_on_port "Test listening on port" 1
	test_accepts_connections "Test accepts connections" 1
	test_accepts_multiple_connections "Test accepts multiple connections" 1
	test_uses_epoll "Test epoll usage" 1
	test_disconnect "Test disconnect" 1
	test_multiple_disconnect "Test multiple disconnect" 1
	test_connect_disconnect_connect "Test connect disconnect connect" 1
	test_multiple_c_d_c "Test multiple connect disconnect connect" 1
	test_unordered_c_d_c "Test unordered connect disconnect connect" 1
	test_replies_http_request "Test replies http request" 3
	test_replies_http_request_1 "Test second replies request" 1
	test_uses_sendfile "Test sendfile uses" 3
	test_get_small_file_wget "Test small file wget" 3
	test_get_small_file_wget_cmp "Test small file wget cmp" 4
	test_get_large_file_wget "Test large file wget" 3
	test_get_large_file_wget_cmp "Test large file wget cmp" 4
	test_get_bad_file_404 "Test bad file 404" 2
	test_bad_path_404 "Test bad path 404" 2
	test_get_one_file_then_another "Test one file then another" 3
	test_get_two_simultaneous_files "Test get two simultaneous files" 4
	test_get_multiple_simultaneous_files "Test multiple simultaneous files" 5
	test_uses_io_submit "Test io submit uses" 3
	test_get_small_dyn_file_wget "Test small dynamic file wget" 3
	test_get_small_dyn_file_wget_cmp "Test small dynamic file wget cmp" 4
	test_get_large_dyn_file_wget "Test large dynamic file wget" 3
	test_get_large_dyn_file_wget_cmp "Test large dynamic file wget cmp" 4
	test_get_bad_dyn_file_404 "Test bad dynamic file 404" 2
	test_get_one_dyn_file_then_another "Test one dynamic file then another" 4
	test_get_two_simultaneous_dyn_files "Test two simultaneous dynamic files" 5
	test_get_mul_sim_dyn_files "Test multiple simultaneous dynamic files" 4
	test_get_two_sim_stat_dyn_files "Test two simultaneous dynamic files stat" 4
	test_get_multiple_simultaneous_stat_dyn_files \
		"Test multiple simultaneous dynamic files stat" 5
	)

# ---------------------------------------------------------------------------- #

# ----------------- Run test ------------------------------------------------- #

if test $# -ne 1; then
	echo "Usage: $0 <test_number> | init | cleanup" 1>&2
	exit 1
fi

test_index=$1

if test $test_index = "init"; then
		init_world
		exit 0
fi

if test $test_index = "cleanup"; then
		cleanup_world
		exit 0
fi

arr_index=$((($test_index - 1) * 3))
last_test=$((${#test_fun_array[@]} / 3))
description=${test_fun_array[$(($arr_index + 1))]}
points=${test_fun_array[$(($arr_index + 2))]}

if test "$test_index" -gt "$last_test" -o "$arr_index" -lt 0; then
		echo "Error: Test index is out range (1 < test_index <= $last_test)." 1>&2
		exit 1
fi

# Run proper function
${test_fun_array[$(($arr_index))]}

exit 0
