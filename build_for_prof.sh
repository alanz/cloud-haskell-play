#!/bin/sh

cabal build timevsthyme --ghc-options="-threaded -prof -auto-all -caf-all -fprof-auto-top -fprof-auto-calls -osuf=.o_p"
