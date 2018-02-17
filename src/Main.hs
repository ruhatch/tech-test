{-# LANGUAGE DeriveDataTypeable  #-}
{-# LANGUAGE DeriveGeneric       #-}
{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE NumDecimals         #-}
{-# LANGUAGE RecordWildCards     #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell     #-}

module Main where

import           Control.Concurrent                                 (forkIO,
                                                                     threadDelay)
import           Control.Concurrent.Async                           (mapConcurrently_)
import           Control.Concurrent.MVar
import           Control.Distributed.Process
import           Control.Distributed.Process.Backend.SimpleLocalnet
import           Control.Distributed.Process.Closure
import           Control.Distributed.Process.Node                   (initRemoteTable)
import           Control.Monad                                      (forM_,
                                                                     void, when)
import           Data.Binary
import           Data.Binary.Orphans                                ()
import           Data.Semigroup                                     hiding
                                                                     (option)
import           Data.Set                                           (Set)
import qualified Data.Set                                           as S
import           Data.Time
import           Data.Typeable
import           GHC.Generics
import           Network.Socket                                     (HostName,
                                                                     ServiceName)
import           Numeric.Natural
import           Options.Applicative
import           System.Random

data GlobalOpts = GlobalOpts
  { optHost    :: HostName
  , optPort    :: ServiceName
  , optCommand :: Command
  }

data Command = Master MasterOpts | Slave

data MasterOpts = MasterOpts
  { optSendFor    :: Natural
  , optWaitFor    :: Natural
  , optSeed       :: Maybe Natural
  , optWithSlaves :: Maybe Natural
  , optKillSlaves :: Bool
  } deriving (Generic, Typeable)

instance Binary MasterOpts

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

sendMessages :: [ProcessId] -> Process ()
sendMessages receivers = do
  n         <- liftIO $ (1 -) <$> randomIO
  timestamp <- liftIO $ getCurrentTime
  nodeId    <- getSelfNode
  forM_ receivers $ flip send $ MyMessage n timestamp nodeId
  liftIO $ threadDelay 5e1

receiveMessages :: MVar MessageSet -> Process ()
receiveMessages messageSet = expectTimeout 1e1 >>= \case
  Nothing -> pure ()
  Just m  -> liftIO $ modifyMVar_ messageSet (pure . S.insert m)

mainProcess :: MasterOpts -> [ProcessId] -> Process ()
mainProcess MasterOpts {..} peers = do
  messageSet <- liftIO $ newMVar S.empty
  timer      <-
    spawnLocal
    . liftIO
    . threadDelay
    $ fromIntegral (optSendFor + optWaitFor)
    * 1e6
  link timer
  void . spawnLocal $ spawnLoopForSeconds (sendMessages peers) optSendFor
  spawnLoopForSeconds (receiveMessages messageSet) (optSendFor + optWaitFor - 1)
  result <- liftIO $ show . calcResult <$> readMVar messageSet
  say result
  unlink timer

slaveProcess :: MasterOpts -> Process ()
slaveProcess opts =
  catch (expect >>= mainProcess opts) (\(_ :: ProcessLinkException) -> pure ())

remotable ['slaveProcess]

main :: IO ()
main = do
  GlobalOpts {..} <- execParser globalOptsParser
  -- setStdGen . mkStdGen . fromIntegral $ fromMaybe 0 optSeed
  backend <- initializeBackend optHost optPort (__remoteTable initRemoteTable)
  case optCommand of

    Master opts@MasterOpts {..} -> do

      case optWithSlaves of
        Nothing -> pure ()
        Just n ->
          void
            .   forkIO
            $   initializeLocalNodes optPort n
            >>= mapConcurrently_ startSlave

      threadDelay 2e6

      startMaster backend $ \slaves -> do
        liftIO . putStrLn $ "Slaves: " <> show slaves
        receivers <- mapM (flip spawn $ $(mkClosure 'slaveProcess) opts) slaves
        void . spawnLocal $ redirectLogsHere backend receivers
        self <- getSelfPid
        forM_ receivers $ flip send (self : receivers)
        catch (mainProcess opts (self : receivers))
              (\(_ :: ProcessLinkException) -> pure ())
        liftIO $ threadDelay 5e6
        when optKillSlaves $ terminateAllSlaves backend

    Slave -> startSlave backend

initializeLocalNodes :: ServiceName -> Natural -> IO [Backend]
initializeLocalNodes basePort n = traverse
  ( \i -> initializeBackend "127.0.0.1"
                            (show $ read basePort + i)
                            (__remoteTable initRemoteTable)
  )
  [1 .. n]

--------------------------------------------------------------------------------
-- Options
--------------------------------------------------------------------------------

globalOptsParser :: ParserInfo GlobalOpts
globalOptsParser = info (helper <*> parser) mempty
 where
  parser =
    GlobalOpts
      <$> strArgument (help "IP address of host to run on" <> metavar "HOST")
      <*> strArgument (help "Port to run on" <> metavar "PORT")
      <*> hsubparser (masterCommand <> slaveCommand)

masterCommand :: Mod CommandFields Command
masterCommand = command "master" (info (Master <$> masterParser) mempty)

slaveCommand :: Mod CommandFields Command
slaveCommand = command "slave" (info (pure Slave) mempty)

masterParser :: Parser MasterOpts
masterParser =
  MasterOpts
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
    <*> optional
          ( option
            auto
            (  help "A number of slaves to run locally"
            <> long "with-slaves"
            <> short 'n'
            <> metavar "n"
            )
          )
    <*> switch (help "Whether to terminate slaves after running" <> long "kill")
