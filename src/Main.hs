{-# LANGUAGE NumDecimals     #-}
{-# LANGUAGE RecordWildCards #-}

module Main where

import           Control.Concurrent               (threadDelay)
import           Control.Distributed.Process
import           Control.Distributed.Process.Node
import           Control.Monad                    (forever)
import           Data.Semigroup                   hiding (option)
import           Network.Transport.TCP            (createTransport,
                                                   defaultTCPParameters)
import           Numeric.Natural
import           Options.Applicative

main :: IO ()
main = do
  Options {..} <- execParser opts
  Right t      <- createTransport "127.0.0.1"
                                  "10501"
                                  ((,) "127.0.0.1")
                                  defaultTCPParameters
  node <- newLocalNode t initRemoteTable
  runProcess node $ do
    (sendPort, recvPort) <- newChan
    spawnLoopForSeconds (sendMessages sendPort) optSendFor
    spawnLoopForSeconds (receiveMessages recvPort) optWaitFor

spawnLoopForSeconds :: Process () -> Natural -> Process ()
spawnLoopForSeconds action seconds = do
  pid <- spawnLocal $ forever action
  liftIO . threadDelay $ fromIntegral seconds * 1e6
  kill pid ""

sendMessages :: SendPort String -> Process ()
sendMessages sendPort = do
  sendChan sendPort "Testing"
  liftIO $ threadDelay 1e5

receiveMessages :: ReceivePort String -> Process ()
receiveMessages recvPort = do
  m <- receiveChan recvPort
  say m

--------------------------------------------------------------------------------
-- Options
--------------------------------------------------------------------------------

data Options = Options
  { optSendFor :: Natural
  , optWaitFor :: Natural
  , optSeed    :: Maybe Natural
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
