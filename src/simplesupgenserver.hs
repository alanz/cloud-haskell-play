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

-- Call and Cast request types. Response types are unnecessary as the GenProcess
-- API uses the Async API, which in turn guarantees that an async handle can
-- /only/ give back a reply for that *specific* request through the use of an
-- anonymous middle-man (as the sender and reciever in our case).

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
  let server = serverDefinition
  serve startCount init' server
  logMessage "startCounter:started"
  return ()
  where init' :: InitHandler Int Int
        init' count = return $ InitOk count Infinity

-- | The ChildSpec includes a 'childRegName', so the pid can be looked
-- up in the registry
getServerPid :: Process ProcessId
getServerPid = do
  mpid <- whereis counterName
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

    nc1 <- incCount
    logMessage $ "after incCount:" ++ show nc1
    nc2 <- incCount
    logMessage $ "current counter:" ++ show nc2
    nc3 <- incCount
    logMessage $ "current counter:" ++ show nc3
    nc4 <- incCount
    logMessage $ "current counter:" ++ show nc4

    s2 <- statistics r
    logMessage $ "stats:" ++ show s2
    -- reportAlive r

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
  , childRegName = Just (LocalName counterName)
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
   RestartAll {intensity = RestartLimit {maxR = maxRestarts 2,
                                         maxT = seconds 1},
               mode = RestartEach {order = LeftToRight}}

-- ---------------------------------------------------------------------
