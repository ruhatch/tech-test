{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE DeriveGeneric      #-}
{-# LANGUAGE LambdaCase         #-}
{-# LANGUAGE NumDecimals        #-}
{-# LANGUAGE RecordWildCards    #-}

module Main where

import           Control.Arrow                                      (second)
import           Control.Concurrent                                 (threadDelay)
import           Control.Concurrent.Async                           (mapConcurrently_)
import           Control.Concurrent.MVar
import           Control.Distributed.Process
import           Control.Distributed.Process.Backend.SimpleLocalnet
import           Control.Distributed.Process.Node                   (forkProcess,
                                                                     initRemoteTable,
                                                                     runProcess)
import           Control.Monad                                      (forM_,
                                                                     void)
import           Data.Binary
import           Data.Binary.Orphans                                ()
import           Data.Maybe                                         (fromMaybe)
import           Data.Semigroup                                     hiding
                                                                     (option)
import           Data.Set                                           (Set)
import qualified Data.Set                                           as S
import           Data.Time
import           Data.Typeable
import           GHC.Generics
import           Numeric.Natural
import           Options.Applicative
import qualified Say                                                as Say
import           System.Random

main :: IO ()
main = do
  options@Options {..} <- execParser opts
  setStdGen . mkStdGen . fromIntegral $ fromMaybe 0 optSeed
  backends <- readNodeFile optNodeFile
  mapConcurrently_ (runBackend options) backends
  threadDelay 2e6

runBackend :: Options -> Backend -> IO ()
runBackend Options {..} backend = do
  node          <- newLocalNode backend

  messageSet    <- newMVar S.empty
  receiverStart <- newEmptyMVar
  receiverDone  <- newEmptyMVar
  receiverId    <- forkProcess node $ do
    void $ liftIO $ takeMVar receiverStart
    spawnLoopForSeconds (receiveMessages messageSet) (optSendFor + optWaitFor)
    Say.sayString "Calculating result"
    result <- liftIO $ show . calcResult <$> readMVar messageSet
    nodeId <- getSelfNode
    Say.sayString $ show nodeId <> ": " <> result
    liftIO $ putMVar receiverDone ()
  runProcess node $ register "receiver" receiverId

  peers <- findPeers backend 5e6

  runProcess node $ do
    Say.sayString $ "Found " <> show (length peers) <> " nodes"
    Say.sayString $ show peers

  putMVar receiverStart ()
  runProcess node $ spawnLoopForSeconds (sendMessages peers) optSendFor
  takeMVar receiverDone

-- | Loop a @Process@ for @seconds@ seconds
spawnLoopForSeconds :: Process () -> Natural -> Process ()
spawnLoopForSeconds m seconds = do
  pid <- spawnLocal $ liftIO . threadDelay $ fromIntegral seconds * 1e6
  withMonitor_ pid go
 where
  go = do
    m
    receiveTimeout 0 [match (\(ProcessMonitorNotification _ _ _) -> pure ())]
      >>= \case
            Just () -> pure ()
            Nothing -> go

sendMessages :: [NodeId] -> Process ()
sendMessages nodes = do
  n         <- liftIO $ (1 -) <$> randomIO
  timestamp <- liftIO $ getCurrentTime
  nodeId    <- getSelfNode
  forM_ nodes
    $ \node -> nsendRemote node "receiver" $ MyMessage n timestamp nodeId
  liftIO $ threadDelay 1e1

receiveMessages :: MVar MessageSet -> Process ()
receiveMessages messageSet = expectTimeout 1e2 >>= \case
  Nothing -> pure ()
  Just m  -> liftIO $ modifyMVar_ messageSet (pure . S.insert m)

--------------------------------------------------------------------------------
-- MyMessage
--------------------------------------------------------------------------------

data MyMessage = MyMessage
  { number    :: Double
  , timestamp :: UTCTime
  , nodeId    :: NodeId
  } deriving (Eq, Generic, Show, Typeable)

instance Ord MyMessage where
  compare m1 m2 = compare (timestamp m1) (timestamp m2)

instance Binary MyMessage

--------------------------------------------------------------------------------
-- MessageSet
--------------------------------------------------------------------------------

type MessageSet = Set MyMessage

calcResult :: MessageSet -> (Int, Double)
calcResult set = (S.size set, sumProd)
  where sumProd = sum $ zipWith (\i m -> i * number m) [1 ..] (S.toAscList set)

--------------------------------------------------------------------------------
-- Node File
--------------------------------------------------------------------------------

-- | Read a node file with an ip:port on each line
readNodeFile :: FilePath -> IO [Backend]
readNodeFile file = do
  names <- map (second tail . break (== ':')) . lines <$> readFile file
  traverse initializeBackend' names
 where
  initializeBackend' (ip, port) = initializeBackend ip port initRemoteTable

--------------------------------------------------------------------------------
-- Options
--------------------------------------------------------------------------------

data Options = Options
  { optSendFor  :: Natural
  , optWaitFor  :: Natural
  , optSeed     :: Maybe Natural
  , optNodeFile :: FilePath
  }

opts :: ParserInfo Options
opts = info (helper <*> parser) mempty
 where
  parser =
    Options
      <$> option
            auto
            (  help "Number of seconds to send messages for"
            <> long "send-for"
            <> short 'k'
            <> metavar "k"
            )
      <*> option
            auto
            (  help "Number of seconds to wait until killing program"
            <> long "wait-for"
            <> short 'l'
            <> metavar "l"
            )
      <*> optional
            ( option
              auto
              (  help "Seed for the random number generator"
              <> long "with-seed"
              <> short 's'
              <> metavar "s"
              )
            )
      <*> strOption
            (  help "Path to a node specification file"
            <> long "node-file"
            <> short 'f'
            <> metavar "NODE_FILE"
            )
