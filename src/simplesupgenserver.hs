{-# LANGUAGE DeriveDataTypeable   #-}
{-# LANGUAGE DeriveGeneric        #-}
{-# LANGUAGE ScopedTypeVariables  #-}
{-# LANGUAGE TemplateHaskell      #-}

-- | Tutorial example based on
-- http://haskell-distributed-next.github.io/tutorials/ch-tutorial1.html

import Control.Concurrent (threadDelay)
import Control.Distributed.Process.Node
import Network.Transport.TCP (createTransport, defaultTCPParameters)
import Control.Distributed.Process hiding (call, monitor)
import Control.Distributed.Process.Closure
import Control.Distributed.Process.Platform hiding (__remoteTable, send)
import Control.Distributed.Process.Platform.ManagedProcess hiding (runProcess)
import Control.Exception (SomeException)
import Control.Distributed.Process.Platform.Supervisor hiding (start, shutdown)
import Control.Distributed.Process.Platform.Time
import Control.Distributed.Process.Platform.Timer
import Control.Distributed.Process.Serializable()
import Data.Binary
import Data.Typeable (Typeable)
import GHC.Generics
import qualified Control.Distributed.Process.Platform.Supervisor as Supervisor

{-
#if !MIN_VERSION_base(4,6,0)
import Prelude hiding (catch)
#endif
-}

replyBack :: (ProcessId, String) -> Process ()
replyBack (sender, msg) = send sender msg

logMessage :: String -> Process ()
logMessage msg = say msg

-- =========================================================================================
-- ---------------------------------------------------------------------
-- Simple gen_server copied from the distributed-process-platform tests

--------------------------------------------------------------------------------
-- Types                                                                      --
--------------------------------------------------------------------------------

data Increment = Increment
  deriving (Typeable, Generic, Eq, Show)
instance Binary Increment where

data Fetch = Fetch
  deriving (Typeable, Generic, Eq, Show)
instance Binary Fetch where

data Reset = Reset
  deriving (Typeable, Generic, Eq, Show)
instance Binary Reset where

type State = Int

--------------------------------------------------------------------------------
-- API                                                                        --
--------------------------------------------------------------------------------

-- | Increment count
incCount :: Process Int
incCount = do
  sid <- getServerPid
  call sid Increment

-- | Get the current count - this is replicating what 'call' actually does
getCount :: Process Int
getCount = do
  sid <- getServerPid
  call sid Fetch

-- | Reset the current count
resetCount :: Process ()
resetCount = do
  sid <- getServerPid
  cast sid Reset

-- | Start a counter server
startCounter :: Int -> Process ()
startCounter startCount = do
  logMessage "startCounter:starting"
  self <- getSelfPid
  register counterName self
  serve startCount init' serverDefinition
  where init' :: InitHandler Int Int
        init' count = return $ InitOk count Infinity

-- | The ChildSpec includes a 'childRegName', so the pid can be looked
-- up in the registry
getServerPid :: Process ProcessId
getServerPid = do
  mpid <- whereis counterName
  logMessage $ "getServerPid:" ++ show mpid
  sleepFor 200 Millis
  case mpid of
    Just pid -> return pid
    Nothing -> do
      logMessage "getServerPid failed"
      error "blow up"

counterName = "countername"

--------------------------------------------------------------------------------
-- Implementation                                                             --
--------------------------------------------------------------------------------

serverDefinition :: ProcessDefinition State
serverDefinition = defaultProcess {
     apiHandlers = [
          handleCallIf (condition (\count Increment -> count >= 10))-- invariant
                       (\_ (_ :: Increment) -> haltMaxCount)

        , handleCall handleIncrement
        , handleCall (\count Fetch -> reply count count)
        , handleCast (\_ Reset -> continue 0)
        ]
    } :: ProcessDefinition State

haltMaxCount :: Process (ProcessReply Int State)
haltMaxCount = haltNoReply_ (ExitOther "Count > 10")

handleIncrement :: State -> Increment -> Process (ProcessReply Int State)
handleIncrement count Increment =
    let next = count + 1 in continue next >>= replyWith next



-- ==========================================================================================
-- ---------------------------------------------------------------------
-- Note: this TH stuff has to be before anything that refers to it

$(remotable [ 'startCounter
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
    r <- Supervisor.start restartStrategy [(permChild $ RunClosure ($(mkClosure 'startCounter) (8::Int)))]

    -- r <- startCounter 0
    logMessage "started"
    sleepFor 200 Millis

    doIncCount 200
    doIncCount 200

    -- The supervised process will die as a result of the next call
    catchOp incCount
    logMessage $ "after catchOp 1"
    sleepFor 200 Millis

    -- Running against restarted worker
    doIncCount 200
    doIncCount 200

    s1 <- statistics r
    logMessage $ "stats:" ++ show s1

    -- The supervised process will die as a result of the next call,
    -- but not be restarted due to the maxRestarts value of 2
    sleepFor 6000 Millis -- make sure we pass the maxT of 1 sec first
    catchOp incCount
    logMessage $ "after catchOp 2"
    sleepFor 200 Millis

    logMessage "after second restart"
    doIncCount 200
    doIncCount 200

    catchOp incCount
    logMessage $ "after catchOp 3"
    sleepFor 200 Millis

    doIncCount 200

    logMessage $ "getting stats"
    s2 <- statistics r
    logMessage $ "stats:" ++ show s2
    sleepFor 200 Millis

    return ()

  -- A 1 second wait. Otherwise the main thread can terminate before
  -- our messages reach the logging process or get flushed to stdio
  threadDelay (1*1000000)
  return ()

doIncCount :: Int -> Process ()
doIncCount delay = do
  nc <- incCount
  logMessage $ "after incCount:" ++ show nc
  sleepFor delay Millis


catchOp :: Process a -> Process ()
catchOp op = catch (op >> return ()) handler
  where
    handler :: SomeException -> Process ()
    handler e = do
      logMessage $ "catchOp caught exception:" ++ show e

-- ---------------------------------------------------------------------

restartStrategy :: RestartStrategy
restartStrategy =
   RestartAll {intensity = RestartLimit {maxR = maxRestarts 1,
                                         maxT = seconds 5},
               mode = RestartEach {order = LeftToRight}}

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
  , childRegName = Nothing
  }

tempWorker :: ChildStart -> ChildSpec
tempWorker clj =
  (defaultWorker clj)
  {
    childKey     = "temp-worker"
  , childRestart = Temporary
  }


-- ---------------------------------------------------------------------
