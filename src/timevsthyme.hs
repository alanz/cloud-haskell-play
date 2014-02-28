{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell     #-}
{-# LANGUAGE DeriveGeneric             #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveDataTypeable #-}

import Control.Concurrent (threadDelay)
import Control.Distributed.Process hiding (call, monitor,Message)
import Control.Distributed.Process.Node
import Control.Distributed.Process.Platform hiding (__remoteTable,send,sendChan)
import Control.Distributed.Process.Platform.ManagedProcess hiding (runProcess)
import Control.Distributed.Process.Platform.Time
import Control.Distributed.Process.Platform.Timer
import Control.Distributed.Process.Serializable()
import Data.AffineSpace
import Data.Binary
import Data.Typeable (Typeable)
import GHC.Generics
import Network.Transport.TCP (createTransport, defaultTCPParameters)
import qualified Control.Distributed.Process.Platform (__remoteTable)

import qualified Data.Thyme.Clock as  N
import qualified Data.Thyme.Format as N -- Needed for Show instances
import qualified ThymeUtil as N

import qualified Data.Time.Clock  as O
import qualified Control.Distributed.Process.Platform.Time as O

testOld :: Bool
-- testOld = True
testOld = False

numToSend :: Int
numToSend = 10000

logm :: String -> Process ()
logm msg = say msg


-- ---------------------------------------------------------------------

myRemoteTable :: RemoteTable
myRemoteTable =
  Control.Distributed.Process.Platform.__remoteTable initRemoteTable

main :: IO ()
main = do
  Right t <- createTransport "127.0.0.1" "10501" defaultTCPParameters
  node <- newLocalNode t myRemoteTable

  runProcess node $ do
    s1 <- launchServer
    s2 <- launchServer
    logm $ "servers launched"
    sleepFor 1 Seconds

    sid <- getSelfPid
    startTime <- liftIO $ N.getCurrentTime
    logm "starting callers"
    if testOld
    then do
      spawnLocal $ (mapM_ (\n -> {- sleepFor 10 Micros >> -} stampOld s1)  [1 .. numToSend] >> send sid "ao")
      spawnLocal $ (mapM_ (\n -> {- sleepFor 10 Micros >> -} stampOld s2)  [1 .. numToSend] >> send sid "bo")
    else do
      spawnLocal $ (mapM_ (\n -> {- sleepFor 10 Micros >> -} stampNew s1)  [1 .. numToSend] >> send sid "an")
      spawnLocal $ (mapM_ (\n -> {- sleepFor 10 Micros >> -} stampNew s2)  [1 .. numToSend] >> send sid "bn")

    done1 <- expect :: Process String
    logm $ "got done1:" ++ show done1
    done2 <- expect :: Process String
    logm $ "got done2:" ++ show done2
    endTime <- liftIO $ N.getCurrentTime

    logm $ "(testOld,numToSend)=" ++ show (testOld,numToSend)
    logm $ "took: " ++ show (endTime .-. startTime)

    sleepFor 2 Seconds

    done s1
    done s2

    -- stampOld s1

    sleepFor 5 Seconds

    return ()


  -- A 1 second wait. Otherwise the main thread can terminate before
  -- our messages reach the logging process or get flushed to stdio
  threadDelay (1*1000000)
  return ()


timestamp :: Process String
timestamp = do
  ts <- liftIO $ O.getCurrentTime
  return $ show ts

thymestamp :: Process String
thymestamp = do
  ts <- liftIO $ N.getCurrentTime
  return $ show ts

data StampOld  = SO deriving (Typeable,Generic)
data StampNew  = SN deriving (Typeable,Generic)
data Done  = Done deriving (Typeable,Generic)

instance Binary StampOld where
instance Binary StampNew where
instance Binary Done where

-- public API

stampOld :: ProcessId -> Process String
stampOld sid = call sid SO

stampNew :: ProcessId -> Process String
stampNew sid = call sid SN

done :: ProcessId -> Process ()
done sid = call sid Done


launchServer :: Process ProcessId
launchServer =
  let server = statelessProcess {
      apiHandlers = [
          handleCall_   (\SO -> timestamp  >>= return)
        , handleCall_   (\SN -> thymestamp >>= return)
        , action        (\Done -> {- logm "stopping" >> -} stop_ ExitNormal)
        , action        (\("stop") -> stop_ ExitNormal)
        ]
    }
  in spawnLocal $ serve () (statelessInit Infinity) server

--------------------------------------------
{-
Old
===
*Main> :main
Fri Feb 28 07:48:51 UTC 2014 pid://127.0.0.1:10501:0:10: servers launched
Fri Feb 28 07:48:52 UTC 2014 pid://127.0.0.1:10501:0:10: starting callers
Fri Feb 28 07:50:25 UTC 2014 pid://127.0.0.1:10501:0:10: got done1:'a'
Fri Feb 28 07:50:25 UTC 2014 pid://127.0.0.1:10501:0:10: got done2:'b'
*** Exception: exit-from=pid://127.0.0.1:10501:0:10
*Main> 

60 + 25 + 8 = 93 secs

*Main> :main
Fri Feb 28 08:17:59 UTC 2014 pid://127.0.0.1:10501:0:10: servers launched
Fri Feb 28 08:18:00 UTC 2014 pid://127.0.0.1:10501:0:10: starting callers
Fri Feb 28 08:18:01 UTC 2014 pid://127.0.0.1:10501:0:10: got done1:"ao"
Fri Feb 28 08:18:01 UTC 2014 pid://127.0.0.1:10501:0:10: got done2:"bo"
Fri Feb 28 08:18:01 UTC 2014 pid://127.0.0.1:10501:0:10: (testOld,numToSend)=(True,10000)
Fri Feb 28 08:18:01 UTC 2014 pid://127.0.0.1:10501:0:10: took: 1.760791s

i.e. 0.176 ms per call

alanz@alanz-laptop:~/mysrc/github/alanz/cloud-haskell-play$ ./run_prof.sh 
Fri Feb 28 08:49:09 UTC 2014 pid://127.0.0.1:10501:0:10: servers launched
Fri Feb 28 08:49:10 UTC 2014 pid://127.0.0.1:10501:0:10: starting callers
Fri Feb 28 08:49:12 UTC 2014 pid://127.0.0.1:10501:0:10: got done1:"bo"
Fri Feb 28 08:49:12 UTC 2014 pid://127.0.0.1:10501:0:10: got done2:"ao"
Fri Feb 28 08:49:12 UTC 2014 pid://127.0.0.1:10501:0:10: (testOld,numToSend)=(True,10000)
Fri Feb 28 08:49:12 UTC 2014 pid://127.0.0.1:10501:0:10: took: 2.272632s
timevsthyme: exit-from=pid://127.0.0.1:10501:0:10
Wrote timevsthyme.prof.html

i.e. 0.227ms per call

without profiling, sincle core
alanz@alanz-laptop:~/mysrc/github/alanz/cloud-haskell-play$ ./dist/build/timevsthyme/timevsthyme
Fri Feb 28 08:57:21 UTC 2014 pid://127.0.0.1:10501:0:10: servers launched
Fri Feb 28 08:57:22 UTC 2014 pid://127.0.0.1:10501:0:10: starting callers
Fri Feb 28 08:57:23 UTC 2014 pid://127.0.0.1:10501:0:10: got done1:"ao"
Fri Feb 28 08:57:23 UTC 2014 pid://127.0.0.1:10501:0:10: got done2:"bo"
Fri Feb 28 08:57:23 UTC 2014 pid://127.0.0.1:10501:0:10: (testOld,numToSend)=(True,10000)
Fri Feb 28 08:57:23 UTC 2014 pid://127.0.0.1:10501:0:10: took: 1.3881s

so 0.138ms

without profileing, 4 cores
alanz@alanz-laptop:~/mysrc/github/alanz/cloud-haskell-play$ ./dist/build/timevsthyme/timevsthyme +RTS -N4
Fri Feb 28 08:58:21 UTC 2014 pid://127.0.0.1:10501:0:10: servers launched
Fri Feb 28 08:58:22 UTC 2014 pid://127.0.0.1:10501:0:10: starting callers
Fri Feb 28 08:58:24 UTC 2014 pid://127.0.0.1:10501:0:10: got done1:"bo"
Fri Feb 28 08:58:24 UTC 2014 pid://127.0.0.1:10501:0:10: got done2:"ao"
Fri Feb 28 08:58:24 UTC 2014 pid://127.0.0.1:10501:0:10: (testOld,numToSend)=(True,10000)
Fri Feb 28 08:58:24 UTC 2014 pid://127.0.0.1:10501:0:10: took: 1.276079s

so 0.128ms

New
===

*Main> :main
Fri Feb 28 07:51:32 UTC 2014 pid://127.0.0.1:10501:0:10: servers launched

Fri Feb 28 07:51:33 UTC 2014 pid://127.0.0.1:10501:0:10: starting callers
Fri Feb 28 07:53:00 UTC 2014 pid://127.0.0.1:10501:0:10: got done1:'b'
Fri Feb 28 07:53:00 UTC 2014 pid://127.0.0.1:10501:0:10: got done2:'a'
*** Exception: exit-from=pid://127.0.0.1:10501:0:10

27 + 60 = 87 secs

*Main> :main
Fri Feb 28 08:16:19 UTC 2014 pid://127.0.0.1:10501:0:10: servers launched
Fri Feb 28 08:16:20 UTC 2014 pid://127.0.0.1:10501:0:10: starting callers
Fri Feb 28 08:16:22 UTC 2014 pid://127.0.0.1:10501:0:10: got done1:"an"
Fri Feb 28 08:16:22 UTC 2014 pid://127.0.0.1:10501:0:10: got done2:"bn"
Fri Feb 28 08:16:22 UTC 2014 pid://127.0.0.1:10501:0:10: (testOld,numToSend)=(False,10000)
Fri Feb 28 08:16:22 UTC 2014 pid://127.0.0.1:10501:0:10: took: 1.692658s

i.e. 0.169ms per call

alanz@alanz-laptop:~/mysrc/github/alanz/cloud-haskell-play$ ./run_prof.sh 
Fri Feb 28 08:52:08 UTC 2014 pid://127.0.0.1:10501:0:10: servers launched
Fri Feb 28 08:52:09 UTC 2014 pid://127.0.0.1:10501:0:10: starting callers
Fri Feb 28 08:52:11 UTC 2014 pid://127.0.0.1:10501:0:10: got done1:"an"
Fri Feb 28 08:52:11 UTC 2014 pid://127.0.0.1:10501:0:10: got done2:"bn"
Fri Feb 28 08:52:11 UTC 2014 pid://127.0.0.1:10501:0:10: (testOld,numToSend)=(False,10000)
Fri Feb 28 08:52:11 UTC 2014 pid://127.0.0.1:10501:0:10: took: 1.894375s
timevsthyme: exit-from=pid://127.0.0.1:10501:0:10
Wrote timevsthyme.prof.html

i.e. 0.189ms per call

Without profiling, single core

alanz@alanz-laptop:~/mysrc/github/alanz/cloud-haskell-play$ ./dist/build/timevsthyme/timevsthyme
Fri Feb 28 08:55:47 UTC 2014 pid://127.0.0.1:10501:0:10: servers launched
Fri Feb 28 08:55:48 UTC 2014 pid://127.0.0.1:10501:0:10: starting callers
Fri Feb 28 08:55:49 UTC 2014 pid://127.0.0.1:10501:0:10: got done1:"an"
Fri Feb 28 08:55:49 UTC 2014 pid://127.0.0.1:10501:0:10: got done2:"bn"
Fri Feb 28 08:55:49 UTC 2014 pid://127.0.0.1:10501:0:10: (testOld,numToSend)=(False,10000)
Fri Feb 28 08:55:49 UTC 2014 pid://127.0.0.1:10501:0:10: took: 1.141852s
tim

so 0.114 ms per call

Without profiling, 4 cores

alanz@alanz-laptop:~/mysrc/github/alanz/cloud-haskell-play$ ./dist/build/timevsthyme/timevsthyme +RTS -N4
Fri Feb 28 08:59:21 UTC 2014 pid://127.0.0.1:10501:0:10: servers launched
Fri Feb 28 08:59:22 UTC 2014 pid://127.0.0.1:10501:0:10: starting callers
Fri Feb 28 08:59:23 UTC 2014 pid://127.0.0.1:10501:0:10: got done1:"bn"
Fri Feb 28 08:59:23 UTC 2014 pid://127.0.0.1:10501:0:10: got done2:"an"
Fri Feb 28 08:59:23 UTC 2014 pid://127.0.0.1:10501:0:10: (testOld,numToSend)=(False,10000)
Fri Feb 28 08:59:23 UTC 2014 pid://127.0.0.1:10501:0:10: took: 1.053731s

so 0.105ms


Summary
===================================

No profiling
           old      new      ratio
1 core    0.138ms  0.114ms     0.826
4 cores   0.128ms  0.105ms     0.820

-}
