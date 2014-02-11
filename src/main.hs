{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell     #-}
{-# LANGUAGE DeriveGeneric             #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE DataKinds #-}

-- | Tutorial example based on
-- http://haskell-distributed-next.github.io/tutorials/ch-tutorial1.html

import Control.Concurrent (threadDelay)
import Control.Monad (forever)
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
import Control.Distributed.Process hiding (call, monitor,Message)
import Control.Distributed.Process.Closure
import Control.Distributed.Process.Node
import Control.Distributed.Process.Platform hiding (__remoteTable, send,sendChan)
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

import Data.Binary (Binary,get,put)
import Data.Typeable (Typeable)

import GHC.Generics

import Control.Distributed.Process.Platform.Execution.Exchange
import qualified Control.Distributed.Process.Platform (__remoteTable)

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

myRemoteTable :: RemoteTable
myRemoteTable =
  Control.Distributed.Process.Platform.__remoteTable initRemoteTable

main :: IO ()
main = do
  Right t <- createTransport "127.0.0.1" "10501" defaultTCPParameters
  node <- newLocalNode t myRemoteTable

  runProcess node $ do
    (sp, rp) <- newChan :: Process (Channel Int)

    rex <- messageKeyRouter PayloadOnly

    -- Since the /router/ doesn't offer a syncrhonous start
    -- option, we use spawnSignalled to get the same effect,
    -- making it more likely (though it's not guaranteed) that
    -- the spawned process will be bound to the routing exchange
    -- prior to our evaluating 'routeMessage' below.
    void $ spawnSignalled (bindKey "foobar" rex) $ const $ do
      receiveWait [ match (\(s :: Int) -> sendChan sp s) ]

    routeMessage rex (createMessage "foobar" [] (123 :: Int))
    r <- receiveChan rp
    logMessage $ "receiveChan got:" ++ show r
    sleepFor 2 Seconds

    return ()


  -- A 1 second wait. Otherwise the main thread can terminate before
  -- our messages reach the logging process or get flushed to stdio
  threadDelay (1*1000000)
  return ()

