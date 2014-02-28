#!/bin/sh

# Get data by cost centre
#./dist/build/timevsthyme/timevsthyme +RTS -hc -RTS
#./dist/build/timevsthyme/timevsthyme +RTS -hc -xc -RTS
#./dist/build/timevsthyme/timevsthyme +RTS -hc -xt -RTS
#./dist/build/timevsthyme/timevsthyme +RTS -hc -p -RTS
#./dist/build/timevsthyme/timevsthyme +RTS -hc -p  -RTS
#./dist/build/timevsthyme/timevsthyme +RTS -hc -p -xc  -N 4 -RTS
#./dist/build/timevsthyme/timevsthyme +RTS -hc -p   -N4 -RTS
./dist/build/timevsthyme/timevsthyme +RTS -hc -p  -RTS

# Get data by originating module
#./dist/build/timevsthyme/timevsthyme +RTS -hm -RTS
#./dist/build/timevsthyme/timevsthyme +RTS -hmData.TimevsthymeMnesia -RTS
#./dist/build/timevsthyme/timevsthyme +RTS -hmData.TimevsthymeQueue -RTS

# Get data by closure description
#./dist/build/timevsthyme/timevsthyme +RTS -hd -p -xc -RTS

# Get data by type
#./dist/build/timevsthyme/timevsthyme +RTS -hy -RTS

# Get data by retainer set
#./dist/build/timevsthyme/timevsthyme +RTS -hr -RTS

# Get data by biography
#./dist/build/timevsthyme/timevsthyme +RTS -hb -RTS
#./dist/build/timevsthyme/timevsthyme +RTS -hc -hbdrag,void -RTS

profiteur timevsthyme.prof


