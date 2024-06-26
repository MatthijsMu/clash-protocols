{-# language FlexibleContexts #-}
{-# language NumericUnderscores #-}

module Test.Protocols.Packetstream.Depacketizer
  (tests, depacketizerModel, depacketizeToDfModel) where

-- hedgehog
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range

-- tasty
import Test.Tasty
import Test.Tasty.Hedgehog ( HedgehogTestLimit(HedgehogTestLimit) )
import Test.Tasty.Hedgehog.Extra ( testProperty )
import Test.Tasty.TH ( testGroupGenerator )

import Data.List qualified as L
import Prelude

import Clash.Prelude hiding ( concat )
import Clash.Prelude qualified as C
import Clash.Sized.Vector ( unsafeFromList )

import Protocols.PacketStream

import Test.Protocols.Packetstream.Util


-- | Model of the generic `depacketizerC`.
depacketizerModel
  :: forall (dataWidth :: Nat)
            (headerBytes :: Nat)
            (metaIn :: Type)
            (metaOut :: Type)
            (header :: Type) .
  ( KnownNat dataWidth
  , KnownNat headerBytes
  , 1 <= dataWidth
  , 1 <= headerBytes
  , BitPack header
  , BitSize header ~ headerBytes * 8)
  => (header -> metaIn -> metaOut)
  -> [PacketStreamM2S dataWidth metaIn]
  -> [PacketStreamM2S dataWidth metaOut]
depacketizerModel toMetaOut ps = concat dataWidthPackets
  where
    hdrbytes = natToNum @headerBytes

    parseHdr :: ([PacketStreamM2S 1 metaIn], [PacketStreamM2S 1 metaIn]) -> [PacketStreamM2S 1 metaOut]
    parseHdr (hdrF, fwdF) = fmap (\f -> f { _meta = metaOut }) fwdF
      where
        hdr = bitCoerce $ unsafeFromList @headerBytes $ _data <$> hdrF
        metaOut = toMetaOut hdr (_meta $ L.head fwdF)

    bytePackets :: [[PacketStreamM2S 1 metaIn]]
    bytePackets = L.filter (\fs -> L.length fs > hdrbytes)
                    $ L.concatMap chopPacket . smearAbort <$> chunkByPacket ps

    parsedPackets :: [[PacketStreamM2S 1 metaOut]]
    parsedPackets = parseHdr . L.splitAt hdrbytes <$> bytePackets

    dataWidthPackets :: [[PacketStreamM2S dataWidth metaOut]]
    dataWidthPackets = fmap chunkToPacket . chopBy (C.natToNum @dataWidth) <$> parsedPackets

-- Validate the proof we have conjured from nothing
-- actually passes randomized testing
prop_equivalentBufSizes :: Property
prop_equivalentBufSizes = property $ do
  let divRU n d = div (n + (d - 1)) d

  (headerBytes :: Integer) <- forAll $ Gen.integral $ Range.linear 0 100_000
  (dataWidth :: Integer) <- forAll $ Gen.integral $ Range.linear 1 100_000

  let parseBufSize = dataWidth * headerBytes `divRU` dataWidth - dataWidth + dataWidth
  let forwardBufSize = headerBytes + (dataWidth - (headerBytes `mod` dataWidth)) `mod` dataWidth

  footnote $ "headerBytes: " L.++ show headerBytes
  footnote $ "dataWidth: " L.++ show dataWidth

  parseBufSize === forwardBufSize

tests :: TestTree
tests =
    localOption (mkTimeout 12_000_000 {- 12 seconds -})
  $ localOption (HedgehogTestLimit (Just 1_000_000))
  $(testGroupGenerator)

-- | Model of the generic `depacketizeToDfC`.
depacketizeToDfModel
  :: forall (dataWidth :: Nat)
            (headerBytes :: Nat)
            (meta :: Type)
            (a :: Type)
            (header :: Type) .
  ( KnownNat dataWidth
  , KnownNat headerBytes
  , 1 <= dataWidth
  , 1 <= headerBytes
  , BitPack header
  , BitSize header ~ headerBytes * 8)
  => (header -> meta -> a)
  -> [PacketStreamM2S dataWidth meta]
  -> [a]
depacketizeToDfModel toOut ps = parseHdr <$> bytePackets
  where
    hdrbytes = natToNum @headerBytes

    parseHdr :: [PacketStreamM2S 1 meta] -> a
    parseHdr hdrF = toOut (bitCoerce $ unsafeFromList @headerBytes $ _data <$> hdrF) (_meta $ L.head hdrF)

    bytePackets :: [[PacketStreamM2S 1 meta]]
    bytePackets = L.filter (\fs -> L.length fs >= hdrbytes)
                    $ L.concatMap chopPacket <$> chunkByPacket (dropAbortedPackets ps)
