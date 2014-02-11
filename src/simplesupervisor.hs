{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell     #-}

-- | Tutorial example based on
-- http://haskell-distributed-next.github.io/tutorials/ch-tutorial1.html

import Control.Concurrent (threadDelay)
import Control.Monad (forever)
import Control.Distributed.Process
import Control.Distributed.Process.Node
import Network.Transport.TCP (createTransport, defaultTCPParameters)
import Control.Concurrent.MVar
  ( MVar
  , newMVar
  , putMVar
  , takeMVar
  )
import qualified Control.Exception as Ex
import Control.Exception (throwIO)
import Control.Distributed.Process hiding (call, monitor)
import Control.Distributed.Process.Closure
import Control.Distributed.Process.Node
import Control.Distributed.Process.Platform hiding (__remoteTable, send)
-- import Control.Distributed.Process.Platform as Alt (monitor)
-- import Control.Distributed.Process.Platform.Test
import Control.Distributed.Process.Platform.Time
import Control.Distributed.Process.Platform.Timer
import Control.Distributed.Process.Platform.Supervisor hiding (start, shutdown)
import qualified Control.Distributed.Process.Platform.Supervisor as Supervisor
import Control.Distributed.Process.Platform.ManagedProcess.Client (shutdown)
import Control.Distributed.Process.Serializable()
import Control.Distributed.Static (staticLabel)
import Control.Monad (void, forM_, forM)
import Control.Rematch
  ( equalTo
  , is
  , isNot
  , isNothing
  , isJust
  )

import Data.ByteString.Lazy (empty)
import Data.Maybe (catMaybes)

{-
#if !MIN_VERSION_base(4,6,0)
import Prelude hiding (catch)
#endif
-}

replyBack :: (ProcessId, String) -> Process ()
replyBack (sender, msg) = send sender msg

logMessage :: String -> Process ()
logMessage msg = say msg

-- ---------------------------------------------------------------------
-- Note: this TH stuff has to be before anything that refers to it

exitIgnore :: Process ()
exitIgnore = liftIO $ throwIO ChildInitIgnore

noOp :: Process ()
noOp = return ()

chatty :: ProcessId -> Process ()
chatty me = go 1
  where
    go :: Int -> Process ()
    go 4 = do
      logMessage "exiting"
      return ()
    go n = do
      send me n
      logMessage $ ":sent " ++ show n
      sleepFor 2 Seconds
      go (n + 1)


$(remotable [ 'exitIgnore
            , 'noOp
            , 'chatty
            ])

-- | This is very important, if you do not start the node with this
-- table the supervisor will start and then silently fail when you try
-- to run a closure.
myRemoteTable :: RemoteTable
myRemoteTable = Main.__remoteTable initRemoteTable

-- ---------------------------------------------------------------------

main :: IO ()
main = do
  Right t <- createTransport "127.0.0.1" "10501" defaultTCPParameters
  node <- newLocalNode t myRemoteTable
  -- node <- newLocalNode t initRemoteTable

  runProcess node $ do
    self <- getSelfPid
    r <- Supervisor.start restartAll [(defaultWorker $ RunClosure ($(mkClosure 'chatty) self))]
    -- r <- Supervisor.start restartAll [(permChild $ RunClosure ($(mkClosure 'chatty) self))]
    sleepFor 3 Seconds
    reportAlive r
    logMessage "started"
    s <- statistics r
    logMessage $ "stats:" ++ show s
    reportAlive r

    getMessagesUntilTimeout
    logMessage "getMessagesUntilTimeout returned"

    s2 <- statistics r
    logMessage $ "stats:" ++ show s2
    reportAlive r

    return ()


  -- A 1 second wait. Otherwise the main thread can terminate before
  -- our messages reach the logging process or get flushed to stdio
  threadDelay (1*1000000)
  return ()

-- TODO: I suspect this has to be a handleMessage
getMessagesUntilTimeout :: Process ()
getMessagesUntilTimeout = do
  mm <- expectTimeout (6*1000000) :: Process (Maybe Int)
  case mm of
    Nothing -> do
      logMessage $ "getMessagesUntilTimeout:timed out"
      return ()
    Just m -> do
      logMessage $ "getMessagesUntilTimeout:" ++ show m
      getMessagesUntilTimeout


reportAlive :: ProcessId -> Process ()
reportAlive pid = do
  alive <- isProcessAlive pid
  logMessage $ "pid:" ++ show pid ++ " alive:" ++ show alive

-- ---------------------------------------------------------------------

defaultWorker :: ChildStart -> ChildSpec
defaultWorker clj =
  ChildSpec
  {
    childKey     = ""
  , childType    = Worker
  , childRestart = Temporary
  , childStop    = TerminateImmediately
  , childStart   = clj
  , childRegName = Nothing
  }

permChild :: ChildStart -> ChildSpec
permChild clj =
  (defaultWorker clj)
  {
    childKey     = "perm-child"
  , childRestart = Permanent
  }

tempWorker :: ChildStart -> ChildSpec
tempWorker clj =
  (defaultWorker clj)
  {
    childKey     = "temp-worker"
  , childRestart = Temporary
  }


-- ---------------------------------------------------------------------

restartStrategy :: RestartStrategy
restartStrategy = -- restartAll
   RestartAll {intensity = RestartLimit {maxR = maxRestarts 1,
                                         maxT = seconds 1},
               mode = RestartEach {order = LeftToRight}}

-- ---------------------------------------------------------------------

