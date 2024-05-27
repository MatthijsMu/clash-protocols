{-|
Module      : Protocols.PacketStream.Util
Description : Utility module, only for very small util functions
-}
module Protocols.PacketStream.Util
    ( toMaybe
    ) where

-- | Wrap a value in a Just if True
toMaybe :: Bool -> a -> Maybe a
toMaybe True x = Just x
toMaybe False _ = Nothing
