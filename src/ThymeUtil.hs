{-# LANGUAGE DeriveDataTypeable   #-}
{-# LANGUAGE DeriveGeneric        #-}
{-# LANGUAGE StandaloneDeriving   #-}
{-# LANGUAGE TemplateHaskell      #-}
{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE ScopedTypeVariables  #-}

module ThymeUtil
  (
  -- * Thyme related
    timeIntervalToDiffTime
  , diffTimeToTimeInterval
  , diffTimeToMicroSeconds
  , diffTimeToDelay
  , delayToDiffTime
  , microsecondsToNominalDiffTime
  , microSecondsPerSecond
  )
  where

import Control.Distributed.Process.Platform.Time hiding (delayToDiffTime,timeIntervalToDiffTime,diffTimeToDelay,microsecondsToNominalDiffTime,diffTimeToTimeInterval,NominalDiffTime)
import Control.Distributed.Process hiding (call)
import Control.Lens
import Data.AffineSpace
import Data.Binary
import Data.Ratio ((%))
-- import Data.RefSerialize
import Data.Thyme.Calendar
import Data.Thyme.Clock
import Data.Thyme.Format
import Data.Thyme.Time.Core
import Data.Typeable
import GHC.Generics

-- TODO: give these back into distributed-process-platform

-- | given a @TimeInterval@, provide an equivalent @NominalDiffTim@
timeIntervalToDiffTime :: TimeInterval -> NominalDiffTime
timeIntervalToDiffTime ti = microsecondsToNominalDiffTime (fromIntegral $ asTimeout ti)

-- | given a @NominalDiffTim@@, provide an equivalent @TimeInterval@
diffTimeToTimeInterval :: NominalDiffTime -> TimeInterval
diffTimeToTimeInterval dt = microSeconds $ round $ diffTimeToMicroSeconds dt

{-# INLINE diffTimeToMicroSeconds #-}
diffTimeToMicroSeconds :: (TimeDiff t, Fractional n) => t -> n
diffTimeToMicroSeconds = (* recip 1000) . fromIntegral . view microseconds

-- | given a @NominalDiffTim@@, provide an equivalent @Delay@
diffTimeToDelay :: NominalDiffTime -> Delay
diffTimeToDelay dt = Delay $ diffTimeToTimeInterval dt

-- | given a @Delay@, provide an equivalent @NominalDiffTim@
delayToDiffTime :: Delay -> NominalDiffTime
delayToDiffTime (Delay ti) = timeIntervalToDiffTime ti
delayToDiffTime Infinity   = error "trying to convert Delay.Infinity to a NominalDiffTime"
delayToDiffTime (NoDelay)  = microsecondsToNominalDiffTime 0

-- | Create a 'NominalDiffTime' from a number of microseconds.
microsecondsToNominalDiffTime :: Integer -> NominalDiffTime
-- microsecondsToNominalDiffTime x = fromRational (x % (fromIntegral microSecondsPerSecond))
microsecondsToNominalDiffTime x = fromSeconds (x % microSecondsPerSecond)

{-# INLINE microSecondsPerSecond #-}
microSecondsPerSecond :: Integer
microSecondsPerSecond = 1000000




-- ---------------------------------------------------------------------
