-- | Command-line tool for opening and communicating through magic wormholes.
--
-- Intended to inter-operate with the `wormhole` command-line tool from
-- [magic-wormhole](https://github.com/warner/magic-wormhole).
module Main (main) where

import Protolude

import qualified Options.Applicative as Opt

import qualified Crypto.Spake2 as Spake2
import qualified Data.Aeson as Aeson
import qualified MagicWormhole.Internal.FileTransfer as FileTransfer
import qualified MagicWormhole.Internal.Messages as Messages
import qualified MagicWormhole.Internal.Peer as Peer
import qualified MagicWormhole.Internal.Rendezvous as Rendezvous
import MagicWormhole.Internal.WebSockets (WebSocketEndpoint(..), parseWebSocketEndpoint)

data Options
  = Options
  { cmd :: Command
  , rendezvousEndpoint :: WebSocketEndpoint
  } deriving (Eq, Show)

optionsParser :: Opt.Parser Options
optionsParser
  = Options
  <$> commandParser
  <*> Opt.option
        (Opt.maybeReader parseWebSocketEndpoint)
        ( Opt.long "rendezvous-url" <>
          Opt.help "Endpoint for the Rendezvous server" <>
          Opt.value defaultEndpoint <>
          Opt.showDefault )
  where
    -- | Default URI for rendezvous server.
    --
    -- This is Brian Warner's personal server.
    defaultEndpoint = fromMaybe (panic "Invalid default URL") (parseWebSocketEndpoint "ws://relay.magic-wormhole.io:4000/v1")


data Command
  = Send
  | Receive
  deriving (Eq, Show)

commandParser :: Opt.Parser Command
commandParser = Opt.hsubparser $
  Opt.command "send" (Opt.info (pure Send) (Opt.progDesc "Send a text message, file, or directory")) <>
  Opt.command "receive" (Opt.info (pure Receive) (Opt.progDesc "Receive a text message, file, or directory"))

makeOptions :: Text -> Opt.Parser a -> Opt.ParserInfo a
makeOptions headerText parser = Opt.info (Opt.helper <*> parser) (Opt.fullDesc <> Opt.header (toS headerText))

-- | Execute 'Command' against a Wormhole Rendezvous server.
app :: Command -> Rendezvous.Session -> IO ()
app command session = do
  print command
  nameplate <- Rendezvous.allocate session
  mailbox <- Rendezvous.claim session nameplate
  peer <- Rendezvous.open session mailbox  -- XXX: We should run `close` in the case of exceptions?
  let (Messages.Nameplate n) = nameplate
  Peer.withEncryptedConnection peer (Spake2.makePassword (toS n <> "-potato"))
    (\conn -> do
        let offer = FileTransfer.Message "Brave new world that has such offers in it"
        Peer.sendMessage conn (toS (Aeson.encode offer)))

main :: IO ()
main = do
  options <- Opt.execParser (makeOptions "hocus-pocus - summon and traverse magic wormholes" optionsParser)
  Rendezvous.runClient (rendezvousEndpoint options) appID side (app (cmd options))
  where
    appID = Messages.AppID "jml.io/hocus-pocus"
    side = Messages.Side "treebeard"
