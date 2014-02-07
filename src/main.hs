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
logMessage msg = say $ "handling " ++ msg


-- ---------------------------------------------------------------------
-- Note: this TH stuff has to be before anything that refers to it

exitIgnore :: Process ()
exitIgnore = liftIO $ throwIO ChildInitIgnore

noOp :: Process ()
noOp = return ()

notifyMe :: ProcessId -> Process ()
notifyMe me = getSelfPid >>= send me >> obedient

sleepy :: Process ()
sleepy = (sleepFor 5 Minutes)
           `catchExit` (\_ (_ :: ExitReason) -> return ()) >> sleepy

obedient :: Process ()
obedient = (sleepFor 5 Minutes)
           {- supervisor inserts handlers that act like we wrote:
             `catchExit` (\_ (r :: ExitReason) -> do
                             case r of
                               ExitShutdown -> return ()
                               _ -> die r)
           -}

chatty :: ProcessId -> Process ()
chatty me = do
  pid <- getSelfPid
  go pid 1
  where
    go :: ProcessId -> Int -> Process ()
    go pid 4 = do
      liftIO $ putStrLn $ show pid ++ "exiting"
      return ()
    go pid n = do
      send me n
      liftIO $ putStrLn $ show pid ++ ":sent " ++ show n
      sleepFor 2 Seconds
      go pid (n + 1)


doIO :: Process ()
doIO = do
  liftIO $ putStrLn "doIO:hello"
  return ()

$(remotable [ 'exitIgnore
            , 'noOp
            , 'sleepy
            , 'obedient
            , 'notifyMe
            , 'chatty
            , 'doIO
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

  liftIO $ runProcess node $ do
    self <- getSelfPid
    r <- Supervisor.start restartAll [(defaultWorker $ RunClosure ($(mkClosure 'chatty) self))]
    reportAlive r
    liftIO $ putStrLn $ "started"
    s <- statistics r
    liftIO $ putStrLn $ "stats:" ++ show s
    reportAlive r

    getMessagesUntilTimeout

    liftIO $ putStrLn $ "stats:" ++ show s
    reportAlive r

    return ()


  -- A 1 second wait. Otherwise the main thread can terminate before
  -- our messages reach the logging process or get flushed to stdio
  threadDelay (1*1000000)
  return ()

getMessagesUntilTimeout :: Process ()
getMessagesUntilTimeout = do
  mm <- expectTimeout (20*1000000) :: Process (Maybe Int)
  case mm of
    Nothing -> do
      liftIO $ putStrLn $ "getMessagesUntilTimeout:timed out"
      return ()
    Just m -> do
      liftIO $ putStrLn $ "getMessagesUntilTimeout:" ++ show m
      getMessagesUntilTimeout


reportAlive :: ProcessId -> Process ()
reportAlive pid = do
  alive <- isProcessAlive pid
  liftIO $ putStrLn $ "pid:" ++ show pid ++ " alive:" ++ show alive

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

